//! Hybrid Logical Clock (HLC) for distributed timestamp ordering.
//!
//! HLC combines physical and logical clocks to provide:
//! - Consistent ordering across distributed nodes
//! - Timestamps that never go backwards
//! - Causality tracking (if A happened before B, ts(A) < ts(B))
//!
//! Based on "Logical Physical Clocks and Consistent Snapshots in
//! Globally Distributed Databases" by Kulkarni et al.
#![allow(dead_code)]

use std::cmp::Ordering;
use std::time::{SystemTime, UNIX_EPOCH};

/// Hybrid Logical Clock timestamp.
///
/// Total ordering: compare physical first, then logical, then node_id.
/// This ensures a deterministic order even when clocks are identical.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Hlc {
    /// Physical time component (milliseconds since Unix epoch).
    pub physical: i64,

    /// Logical counter for events at the same physical time.
    /// Increments when physical time doesn't advance.
    pub logical: u32,

    /// Node identifier for tie-breaking between nodes.
    /// Must be unique per client/server instance.
    pub node_id: u32,
}

impl Hlc {
    /// Create a new HLC timestamp.
    pub fn new(physical: i64, logical: u32, node_id: u32) -> Self {
        Self {
            physical,
            logical,
            node_id,
        }
    }

    /// Check if this timestamp happened before another.
    pub fn happened_before(&self, other: &Hlc) -> bool {
        self.cmp(other) == Ordering::Less
    }

    /// Check if this timestamp happened after another.
    pub fn happened_after(&self, other: &Hlc) -> bool {
        self.cmp(other) == Ordering::Greater
    }

    /// Serialize to 16 bytes (big-endian for lexicographic sorting).
    pub fn to_bytes(&self) -> [u8; 16] {
        let mut buf = [0u8; 16];
        buf[0..8].copy_from_slice(&self.physical.to_be_bytes());
        buf[8..12].copy_from_slice(&self.logical.to_be_bytes());
        buf[12..16].copy_from_slice(&self.node_id.to_be_bytes());
        buf
    }

    /// Deserialize from 16 bytes.
    pub fn from_bytes(buf: &[u8; 16]) -> Self {
        Self {
            physical: i64::from_be_bytes(buf[0..8].try_into().unwrap()),
            logical: u32::from_be_bytes(buf[8..12].try_into().unwrap()),
            node_id: u32::from_be_bytes(buf[12..16].try_into().unwrap()),
        }
    }
}

impl Ord for Hlc {
    fn cmp(&self, other: &Self) -> Ordering {
        self.physical
            .cmp(&other.physical)
            .then(self.logical.cmp(&other.logical))
            .then(self.node_id.cmp(&other.node_id))
    }
}

impl PartialOrd for Hlc {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl std::fmt::Display for Hlc {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}@{}", self.physical, self.logical, self.node_id)
    }
}

/// HLC Clock that maintains state and generates timestamps.
///
/// Each node (agent, server, etc.) should have exactly one Clock instance.
/// The clock ensures timestamps are always monotonically increasing.
pub struct Clock {
    /// Last generated timestamp.
    last: Hlc,

    /// This node's unique identifier.
    node_id: u32,
}

impl Clock {
    /// Create a new clock with the given node ID.
    ///
    /// The node_id should be unique across all nodes in the system.
    pub fn new(node_id: u32) -> Self {
        Self {
            last: Hlc::new(0, 0, node_id),
            node_id,
        }
    }

    /// Generate a new timestamp for a local event.
    ///
    /// Uses the system clock but ensures monotonicity - the returned
    /// timestamp is always greater than any previously generated.
    pub fn now(&mut self) -> Hlc {
        let wall_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);
        self.tick(wall_ms)
    }

    /// Generate a timestamp with an explicit wall clock value.
    ///
    /// Useful for testing or when wall clock is provided externally.
    pub fn tick(&mut self, wall_ms: i64) -> Hlc {
        let physical = wall_ms.max(self.last.physical);

        let logical = if physical == self.last.physical {
            self.last.logical + 1
        } else {
            0
        };

        self.last = Hlc::new(physical, logical, self.node_id);
        self.last
    }

    /// Update the clock upon receiving a message with a timestamp.
    ///
    /// Returns a new timestamp that is after both the local clock and
    /// the received timestamp. This ensures causality: if you receive
    /// a message, your next timestamp will be after the sender's.
    pub fn receive(&mut self, msg_ts: Hlc) -> Hlc {
        let wall_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);
        self.update(msg_ts, wall_ms)
    }

    /// Update with explicit wall clock (for testing).
    pub fn update(&mut self, msg_ts: Hlc, wall_ms: i64) -> Hlc {
        // Physical time is max of: wall clock, our last, received
        let max_physical = wall_ms.max(self.last.physical).max(msg_ts.physical);

        // Logical counter depends on which physical times are equal
        let logical = if max_physical == self.last.physical && max_physical == msg_ts.physical {
            // All three are equal - increment max logical
            self.last.logical.max(msg_ts.logical) + 1
        } else if max_physical == self.last.physical {
            // Our physical time wins - increment our logical
            self.last.logical + 1
        } else if max_physical == msg_ts.physical {
            // Message physical time wins - increment their logical
            msg_ts.logical + 1
        } else {
            // Wall clock wins, logical stays 0
            0
        };

        self.last = Hlc::new(max_physical, logical, self.node_id);
        self.last
    }

    /// Get the last generated timestamp without advancing the clock.
    pub fn current(&self) -> Hlc {
        self.last
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hlc_compare_physical_time_takes_precedence() {
        let a = Hlc::new(100, 5, 1);
        let b = Hlc::new(101, 0, 1);

        assert_eq!(a.cmp(&b), Ordering::Less);
        assert!(a.happened_before(&b));
        assert!(b.happened_after(&a));
    }

    #[test]
    fn hlc_compare_logical_breaks_physical_ties() {
        let a = Hlc::new(100, 0, 1);
        let b = Hlc::new(100, 1, 1);

        assert_eq!(a.cmp(&b), Ordering::Less);
        assert!(a.happened_before(&b));
    }

    #[test]
    fn hlc_compare_node_id_breaks_full_ties() {
        let a = Hlc::new(100, 5, 1);
        let b = Hlc::new(100, 5, 2);

        assert_eq!(a.cmp(&b), Ordering::Less);
        assert!(a.happened_before(&b));
    }

    #[test]
    fn hlc_compare_equality() {
        let a = Hlc::new(100, 5, 1);
        let b = Hlc::new(100, 5, 1);

        assert_eq!(a.cmp(&b), Ordering::Equal);
        assert!(!a.happened_before(&b));
        assert!(!a.happened_after(&b));
    }

    #[test]
    fn hlc_to_bytes_from_bytes_roundtrip() {
        let original = Hlc::new(1704067200000, 42, 12345);

        let bytes = original.to_bytes();
        let restored = Hlc::from_bytes(&bytes);

        assert_eq!(original.physical, restored.physical);
        assert_eq!(original.logical, restored.logical);
        assert_eq!(original.node_id, restored.node_id);
    }

    #[test]
    fn hlc_to_bytes_lexicographically_sortable() {
        let a = Hlc::new(100, 1, 1);
        let b = Hlc::new(100, 2, 1);
        let c = Hlc::new(101, 0, 1);

        let bytes_a = a.to_bytes();
        let bytes_b = b.to_bytes();
        let bytes_c = c.to_bytes();

        assert!(bytes_a < bytes_b);
        assert!(bytes_b < bytes_c);
        assert!(bytes_a < bytes_c);
    }

    #[test]
    fn hlc_display() {
        let ts = Hlc::new(1704067200000, 5, 42);
        assert_eq!(format!("{}", ts), "1704067200000.5@42");
    }

    #[test]
    fn clock_tick_is_monotonic_with_advancing_time() {
        let mut clock = Clock::new(1);

        let t1 = clock.tick(1000);
        let t2 = clock.tick(1001);
        let t3 = clock.tick(1002);

        assert!(t1.happened_before(&t2));
        assert!(t2.happened_before(&t3));

        // Logical should be 0 when physical advances
        assert_eq!(t1.logical, 0);
        assert_eq!(t2.logical, 0);
        assert_eq!(t3.logical, 0);
    }

    #[test]
    fn clock_tick_is_monotonic_with_same_time() {
        let mut clock = Clock::new(1);

        let t1 = clock.tick(1000);
        let t2 = clock.tick(1000);
        let t3 = clock.tick(1000);

        assert!(t1.happened_before(&t2));
        assert!(t2.happened_before(&t3));

        // Logical should increment
        assert_eq!(t1.logical, 0);
        assert_eq!(t2.logical, 1);
        assert_eq!(t3.logical, 2);

        // Physical should stay the same
        assert_eq!(t3.physical, 1000);
    }

    #[test]
    fn clock_tick_is_monotonic_with_backwards_time() {
        let mut clock = Clock::new(1);

        let t1 = clock.tick(1000);
        let t2 = clock.tick(999); // Time goes backwards!
        let t3 = clock.tick(998); // Still backwards!

        assert!(t1.happened_before(&t2));
        assert!(t2.happened_before(&t3));

        // Physical should stay at max seen
        assert_eq!(t2.physical, 1000);
        assert_eq!(t3.physical, 1000);

        // Logical should increment
        assert_eq!(t2.logical, 1);
        assert_eq!(t3.logical, 2);
    }

    #[test]
    fn clock_update_advances_past_received_timestamp() {
        let mut clock_a = Clock::new(1);
        let mut clock_b = Clock::new(2);

        // A generates a timestamp at t=1000
        let ts_a = clock_a.tick(1000);

        // B's wall clock is behind at t=500, receives A's message
        let _ = clock_b.tick(500); // B's local event
        let ts_b = clock_b.update(ts_a, 500);

        // B's timestamp should be after A's
        assert!(ts_a.happened_before(&ts_b));

        // B's physical should be at least A's physical
        assert!(ts_b.physical >= ts_a.physical);
    }

    #[test]
    fn clock_update_with_all_equal_physical_times() {
        let mut clock = Clock::new(1);

        // Start at t=1000
        let _ = clock.tick(1000);

        // Receive message also at t=1000 with logical=5
        let msg = Hlc::new(1000, 5, 2);
        let ts = clock.update(msg, 1000);

        // Result should be after both local and message
        assert!(ts.logical > 5);
        assert_eq!(ts.physical, 1000);
    }

    #[test]
    fn clock_update_when_wall_clock_wins() {
        let mut clock = Clock::new(1);

        // Start at t=1000
        let _ = clock.tick(1000);

        // Receive old message, but wall clock has advanced
        let msg = Hlc::new(500, 10, 2);
        let ts = clock.update(msg, 2000);

        // Wall clock should win, logical resets to 0
        assert_eq!(ts.physical, 2000);
        assert_eq!(ts.logical, 0);
    }

    #[test]
    fn clock_update_when_message_physical_wins() {
        let mut clock = Clock::new(1);

        // Start at t=1000
        let _ = clock.tick(1000);

        // Receive message from the future
        let msg = Hlc::new(5000, 3, 2);
        let ts = clock.update(msg, 1500);

        // Message physical should win
        assert_eq!(ts.physical, 5000);
        // Logical should be message logical + 1
        assert_eq!(ts.logical, 4);
    }

    #[test]
    fn clock_current_returns_last_without_advancing() {
        let mut clock = Clock::new(1);

        let t1 = clock.tick(1000);
        let current1 = clock.current();
        let current2 = clock.current();

        assert_eq!(t1.physical, current1.physical);
        assert_eq!(t1.logical, current1.logical);
        assert_eq!(current1.physical, current2.physical);
        assert_eq!(current1.logical, current2.logical);
    }

    #[test]
    fn clock_preserves_node_id() {
        let mut clock = Clock::new(42);

        let t1 = clock.tick(1000);
        let t2 = clock.tick(1001);

        assert_eq!(t1.node_id, 42);
        assert_eq!(t2.node_id, 42);
    }

    #[test]
    fn multiple_clocks_interacting() {
        // Simulate two agents sending messages back and forth
        let mut agent_a = Clock::new(1);
        let mut agent_b = Clock::new(2);

        // A sends to B
        let a1 = agent_a.tick(100);
        let b1 = agent_b.update(a1, 90); // B's clock is behind

        // B sends to A
        let a2 = agent_a.update(b1, 110);

        // A sends to B again
        let b2 = agent_b.update(a2, 95); // B's clock still behind

        // All timestamps should be properly ordered
        assert!(a1.happened_before(&b1));
        assert!(b1.happened_before(&a2));
        assert!(a2.happened_before(&b2));
    }

    #[test]
    fn hlc_handles_negative_physical_time() {
        // Edge case: timestamps before Unix epoch
        let ts = Hlc::new(-1000, 0, 1);

        let bytes = ts.to_bytes();
        let restored = Hlc::from_bytes(&bytes);

        assert_eq!(restored.physical, -1000);
    }

    #[test]
    fn hlc_handles_max_values() {
        let ts = Hlc::new(i64::MAX, u32::MAX, u32::MAX);

        let bytes = ts.to_bytes();
        let restored = Hlc::from_bytes(&bytes);

        assert_eq!(ts.physical, restored.physical);
        assert_eq!(ts.logical, restored.logical);
        assert_eq!(ts.node_id, restored.node_id);
    }
}
