//! Bloom filter implementation for fast path conflict detection.
//!
//! Each session maintains a bloom filter of all paths it has touched.
//! Before landing, we can quickly check if two sessions might have
//! conflicting paths by testing bloom filter intersection.
//!
//! ## Properties
//!
//! - **No false negatives**: if the filter says "not present", it's guaranteed
//! - **Possible false positives**: if the filter says "maybe present", check the actual paths
//! - **Fast intersection**: O(n) where n is filter size in bytes
//!
//! ## Usage
//!
//! ```
//! use hif::core::Bloom;
//!
//! let mut bloom = Bloom::new(1000, 0.01).unwrap(); // 1000 items, 1% FP rate
//!
//! bloom.add("src/main.rs");
//! bloom.add("src/lib.rs");
//!
//! if bloom.may_contain("src/main.rs") {
//!     // Possibly present (check actual data)
//! }
//!
//! if !bloom.may_contain("src/other.rs") {
//!     // Definitely not present
//! }
//! ```

use super::hash;

/// Bloom filter for path conflict detection.
#[derive(Clone, Debug)]
pub struct Bloom {
    /// Bit array storage.
    bits: Vec<u8>,
    /// Number of hash functions to use.
    num_hashes: u32,
}

impl Bloom {
    /// Create a new bloom filter sized for expected number of items.
    ///
    /// # Arguments
    /// - `expected_items`: estimated number of items to be added
    /// - `fp_rate`: desired false positive rate (e.g., 0.01 for 1%)
    ///
    /// The filter will be sized optimally for these parameters.
    pub fn new(expected_items: usize, fp_rate: f64) -> Option<Self> {
        if expected_items == 0 || fp_rate <= 0.0 || fp_rate >= 1.0 {
            return None;
        }

        // Calculate optimal size: m = -n * ln(p) / (ln(2)^2)
        let n = expected_items.max(1) as f64;
        let ln2 = std::f64::consts::LN_2;
        let ln2_sq = ln2 * ln2;
        let m_float = -n * fp_rate.ln() / ln2_sq;

        // Round up to nearest byte, minimum 8 bytes
        let m_bits = (m_float.ceil() as usize).max(64);
        let m_bytes = (m_bits + 7) / 8;

        // Calculate optimal number of hashes: k = (m/n) * ln(2)
        let k_float = (m_bits as f64 / n) * ln2;
        let k = (k_float.ceil() as u32).max(1);

        Some(Self {
            bits: vec![0u8; m_bytes],
            num_hashes: k,
        })
    }

    /// Create a bloom filter with a specific size (for testing or fixed configs).
    #[allow(dead_code)]
    pub fn with_size(size_bytes: usize, num_hashes: u32) -> Self {
        Self {
            bits: vec![0u8; size_bytes],
            num_hashes,
        }
    }

    /// Create a bloom filter from serialized bytes (for deserialization).
    pub fn from_bytes(data: &[u8], num_hashes: u32) -> Self {
        Self {
            bits: data.to_vec(),
            num_hashes,
        }
    }

    /// Add a path to the bloom filter.
    pub fn add(&mut self, path: &str) {
        let h = hash::hash(path.as_bytes());
        self.add_hash(&h);
    }

    /// Add a pre-computed hash to the bloom filter.
    pub fn add_hash(&mut self, h: &hash::Hash) {
        let m = self.bits.len() as u64 * 8;

        // Use double hashing: h_i(x) = h1(x) + i * h2(x) mod m
        // We split the 256-bit hash into two 64-bit values
        let h1 = u64::from_le_bytes(h[0..8].try_into().unwrap());
        let h2 = u64::from_le_bytes(h[8..16].try_into().unwrap());

        for i in 0..self.num_hashes {
            let bit_idx = (h1.wrapping_add((i as u64).wrapping_mul(h2))) % m;
            let byte_idx = (bit_idx / 8) as usize;
            let bit_offset = (bit_idx % 8) as u8;
            self.bits[byte_idx] |= 1 << bit_offset;
        }
    }

    /// Check if a path might be in the bloom filter.
    ///
    /// Returns:
    /// - `true`: possibly present (may be false positive)
    /// - `false`: definitely not present (guaranteed)
    #[allow(dead_code)]
    pub fn may_contain(&self, path: &str) -> bool {
        let h = hash::hash(path.as_bytes());
        self.may_contain_hash(&h)
    }

    /// Check if a pre-computed hash might be in the bloom filter.
    #[allow(dead_code)]
    pub fn may_contain_hash(&self, h: &hash::Hash) -> bool {
        let m = self.bits.len() as u64 * 8;

        let h1 = u64::from_le_bytes(h[0..8].try_into().unwrap());
        let h2 = u64::from_le_bytes(h[8..16].try_into().unwrap());

        for i in 0..self.num_hashes {
            let bit_idx = (h1.wrapping_add((i as u64).wrapping_mul(h2))) % m;
            let byte_idx = (bit_idx / 8) as usize;
            let bit_offset = (bit_idx % 8) as u8;
            if (self.bits[byte_idx] & (1 << bit_offset)) == 0 {
                return false;
            }
        }
        true
    }

    /// Check if two bloom filters might have overlapping items.
    ///
    /// This is the key operation for conflict detection:
    /// - If `intersects` returns `false`, the sessions definitely don't conflict
    /// - If `intersects` returns `true`, check the actual path index
    #[allow(dead_code)]
    pub fn intersects(&self, other: &Bloom) -> bool {
        // Filters must be same size for meaningful comparison
        if self.bits.len() != other.bits.len() {
            return true;
        }

        // Check if any bits are set in both filters
        for (a, b) in self.bits.iter().zip(other.bits.iter()) {
            if (a & b) != 0 {
                return true;
            }
        }
        false
    }

    /// Merge another bloom filter into this one (union).
    ///
    /// After merging, this filter will contain all items from both filters.
    #[allow(dead_code)]
    pub fn merge(&mut self, other: &Bloom) {
        if self.bits.len() != other.bits.len() {
            return;
        }

        for (a, b) in self.bits.iter_mut().zip(other.bits.iter()) {
            *a |= b;
        }
    }

    /// Get the approximate number of items in the filter.
    #[allow(dead_code)]
    pub fn estimate_count(&self) -> usize {
        let set_bits: usize = self.bits.iter().map(|b| b.count_ones() as usize).sum();

        let m = self.bits.len() as f64 * 8.0;
        let k = self.num_hashes as f64;
        let x = set_bits as f64;

        if x >= m {
            return usize::MAX;
        }
        if x == 0.0 {
            return 0;
        }

        let estimate = -(m / k) * (1.0 - x / m).ln();
        if estimate < 0.0 {
            return 0;
        }
        estimate as usize
    }

    /// Get the current fill ratio (0.0 to 1.0).
    #[allow(dead_code)]
    pub fn fill_ratio(&self) -> f64 {
        let set_bits: usize = self.bits.iter().map(|b| b.count_ones() as usize).sum();
        let m = self.bits.len() as f64 * 8.0;
        set_bits as f64 / m
    }

    /// Serialize the bloom filter for storage.
    ///
    /// Format: [4 bytes: num_hashes (little-endian)][bits...]
    pub fn serialize(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(4 + self.bits.len());
        buf.extend_from_slice(&self.num_hashes.to_le_bytes());
        buf.extend_from_slice(&self.bits);
        buf
    }

    /// Deserialize a bloom filter from storage.
    pub fn deserialize(data: &[u8]) -> Option<Self> {
        if data.len() < 4 {
            return None;
        }

        let num_hashes = u32::from_le_bytes(data[0..4].try_into().ok()?);
        let bits_data = &data[4..];

        if bits_data.is_empty() {
            return None;
        }

        Some(Self::from_bytes(bits_data, num_hashes))
    }

    /// Clear all bits in the filter.
    #[allow(dead_code)]
    pub fn clear(&mut self) {
        self.bits.fill(0);
    }

    /// Get the size of the filter in bytes.
    #[allow(dead_code)]
    pub fn size_bytes(&self) -> usize {
        self.bits.len()
    }

    /// Get the size of the filter in bits.
    #[allow(dead_code)]
    pub fn size_bits(&self) -> usize {
        self.bits.len() * 8
    }

    /// Check if the bloom filter is empty (no bits set).
    #[allow(dead_code)]
    pub fn is_empty(&self) -> bool {
        self.bits.iter().all(|&b| b == 0)
    }

    /// Check if this filter is a subset of another.
    #[allow(dead_code)]
    pub fn is_subset_of(&self, other: &Bloom) -> bool {
        if self.bits.len() != other.bits.len() {
            return false;
        }

        for (a, b) in self.bits.iter().zip(other.bits.iter()) {
            if (a & !b) != 0 {
                return false;
            }
        }
        true
    }

    /// Get the number of hash functions.
    pub fn num_hashes(&self) -> u32 {
        self.num_hashes
    }

    /// Get the raw bits.
    #[allow(dead_code)]
    pub fn bits(&self) -> &[u8] {
        &self.bits
    }
}

/// Rollup multiple bloom filters into a single combined filter.
#[allow(dead_code)]
pub fn rollup(filters: &[&Bloom]) -> Option<Bloom> {
    if filters.is_empty() {
        return None;
    }

    let first = filters[0];
    let size_bytes = first.bits.len();
    let num_hashes = first.num_hashes;

    // Verify all filters have compatible parameters
    for filter in &filters[1..] {
        if filter.bits.len() != size_bytes || filter.num_hashes != num_hashes {
            return None;
        }
    }

    let mut bits = vec![0u8; size_bytes];

    for filter in filters {
        for (b, f) in bits.iter_mut().zip(filter.bits.iter()) {
            *b |= f;
        }
    }

    Some(Bloom { bits, num_hashes })
}

/// Create a new bloom filter that is the intersection of two filters.
#[allow(dead_code)]
pub fn intersection(a: &Bloom, b: &Bloom) -> Option<Bloom> {
    if a.bits.len() != b.bits.len() || a.num_hashes != b.num_hashes {
        return None;
    }

    let bits: Vec<u8> = a
        .bits
        .iter()
        .zip(b.bits.iter())
        .map(|(x, y)| x & y)
        .collect();

    Some(Bloom {
        bits,
        num_hashes: a.num_hashes,
    })
}

/// Compute the Jaccard similarity estimate between two bloom filters.
#[allow(dead_code)]
pub fn jaccard_similarity(a: &Bloom, b: &Bloom) -> f64 {
    if a.bits.len() != b.bits.len() {
        return 0.0;
    }

    let mut both_set: usize = 0;
    let mut either_set: usize = 0;

    for (x, y) in a.bits.iter().zip(b.bits.iter()) {
        both_set += (x & y).count_ones() as usize;
        either_set += (x | y).count_ones() as usize;
    }

    if either_set == 0 {
        return 1.0; // Both empty
    }
    both_set as f64 / either_set as f64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bloom_add_and_lookup() {
        let mut bloom = Bloom::new(100, 0.01).unwrap();

        bloom.add("src/main.rs");
        bloom.add("src/lib.rs");
        bloom.add("README.md");

        assert!(bloom.may_contain("src/main.rs"));
        assert!(bloom.may_contain("src/lib.rs"));
        assert!(bloom.may_contain("README.md"));
    }

    #[test]
    fn bloom_definitely_not_present() {
        let mut bloom = Bloom::new(100, 0.01).unwrap();
        bloom.add("exists.txt");

        let mut false_positives = 0;
        for i in 0..100 {
            let path = format!("nonexistent_{}.txt", i);
            if bloom.may_contain(&path) {
                false_positives += 1;
            }
        }

        // Should have very few false positives (expect ~1% rate)
        assert!(false_positives < 10);
    }

    #[test]
    fn bloom_intersects_detects_overlap() {
        let mut bloom1 = Bloom::with_size(128, 7);
        let mut bloom2 = Bloom::with_size(128, 7);

        bloom1.add("shared/file.rs");
        bloom2.add("shared/file.rs");

        assert!(bloom1.intersects(&bloom2));
    }

    #[test]
    fn bloom_merge_combines_filters() {
        let mut bloom1 = Bloom::with_size(128, 7);
        let mut bloom2 = Bloom::with_size(128, 7);

        bloom1.add("path/a.rs");
        bloom2.add("path/b.rs");

        bloom1.merge(&bloom2);

        assert!(bloom1.may_contain("path/a.rs"));
        assert!(bloom1.may_contain("path/b.rs"));
    }

    #[test]
    fn bloom_serialize_and_deserialize() {
        let mut bloom = Bloom::new(100, 0.01).unwrap();
        bloom.add("test/path.rs");
        bloom.add("another/file.txt");

        let serialized = bloom.serialize();
        let restored = Bloom::deserialize(&serialized).unwrap();

        assert!(restored.may_contain("test/path.rs"));
        assert!(restored.may_contain("another/file.txt"));
        assert_eq!(bloom.num_hashes, restored.num_hashes);
        assert_eq!(bloom.bits.len(), restored.bits.len());
    }

    #[test]
    fn bloom_clear_resets_filter() {
        let mut bloom = Bloom::with_size(64, 5);
        bloom.add("test.txt");
        assert!(bloom.may_contain("test.txt"));

        bloom.clear();

        assert!(!bloom.may_contain("test.txt"));
        assert_eq!(bloom.fill_ratio(), 0.0);
    }

    #[test]
    fn bloom_is_empty() {
        let mut bloom = Bloom::with_size(64, 5);
        assert!(bloom.is_empty());

        bloom.add("test");
        assert!(!bloom.is_empty());

        bloom.clear();
        assert!(bloom.is_empty());
    }

    #[test]
    fn rollup_combines_multiple_filters() {
        let mut f1 = Bloom::with_size(128, 7);
        let mut f2 = Bloom::with_size(128, 7);
        let mut f3 = Bloom::with_size(128, 7);

        f1.add("file1.txt");
        f2.add("file2.txt");
        f3.add("file3.txt");

        let combined = rollup(&[&f1, &f2, &f3]).unwrap();

        assert!(combined.may_contain("file1.txt"));
        assert!(combined.may_contain("file2.txt"));
        assert!(combined.may_contain("file3.txt"));
    }

    #[test]
    fn jaccard_similarity_identical_filters() {
        let mut a = Bloom::with_size(64, 5);
        let mut b = Bloom::with_size(64, 5);

        a.add("test.txt");
        b.add("test.txt");

        let similarity = jaccard_similarity(&a, &b);
        assert_eq!(similarity, 1.0);
    }
}
