//! Blake3 hashing utilities for content-addressed storage.
//!
//! This module provides consistent hashing for all mic content:
//! - Blob hashing for file content
//! - Tree hashing for directory structures
//! - Path hashing for bloom filter keys
//!
//! # Example
//!
//! ```
//! use mic::core::hash;
//!
//! let content = b"Hello, World!";
//! let hash = hash::hash_blob(content);
//! let hex = hash::format_hex(&hash);
//! println!("Content hash: {}", hex);
//! ```

/// Hash output size in bytes (256 bits).
pub const HASH_SIZE: usize = 32;

/// A 256-bit Blake3 hash.
pub type Hash = [u8; HASH_SIZE];

/// Hash arbitrary data using Blake3.
#[inline]
pub fn hash(data: &[u8]) -> Hash {
    blake3::hash(data).into()
}

/// Hash a file's content for blob storage.
///
/// Prefixes with "blob\x00" + length for git-like object typing.
/// This ensures different object types with the same content
/// produce different hashes.
pub fn hash_blob(content: &[u8]) -> Hash {
    let mut hasher = blake3::Hasher::new();
    hasher.update(b"blob\x00");

    // Encode length as varint-style prefix
    let len_bytes = encode_length(content.len());
    hasher.update(&len_bytes);

    hasher.update(content);
    hasher.finalize().into()
}

/// Hash a path string for bloom filter indexing.
#[allow(dead_code)]
#[inline]
pub fn hash_path(path: &str) -> Hash {
    let mut hasher = blake3::Hasher::new();
    hasher.update(b"path\x00");
    hasher.update(path.as_bytes());
    hasher.finalize().into()
}

/// Format a hash as a lowercase hexadecimal string.
pub fn format_hex(hash: &Hash) -> String {
    hash.iter().map(|b| format!("{:02x}", b)).collect()
}

/// Parse a hexadecimal string into a hash.
///
/// Returns `None` if the string is not a valid 64-character hex string.
pub fn parse_hex(hex_str: &str) -> Option<Hash> {
    if hex_str.len() != HASH_SIZE * 2 {
        return None;
    }

    let mut hash = [0u8; HASH_SIZE];
    for (i, chunk) in hex_str.as_bytes().chunks(2).enumerate() {
        let high = hex_digit(chunk[0])?;
        let low = hex_digit(chunk[1])?;
        hash[i] = (high << 4) | low;
    }
    Some(hash)
}

/// Convert a hex ASCII character to its numeric value.
fn hex_digit(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        b'A'..=b'F' => Some(c - b'A' + 10),
        _ => None,
    }
}

/// Encode a length as a variable-length byte sequence.
fn encode_length(mut len: usize) -> Vec<u8> {
    if len == 0 {
        return vec![0];
    }

    let mut bytes = Vec::with_capacity(8);
    while len > 0 {
        bytes.push((len & 0x7f) as u8);
        len >>= 7;
        if len > 0 {
            *bytes.last_mut().unwrap() |= 0x80;
        }
    }
    bytes
}

/// An entry in a tree (directory) for hashing purposes.
pub struct TreeEntry<'a> {
    /// File mode (permissions/type).
    pub mode: u32,
    /// File path relative to tree root.
    pub path: &'a str,
    /// Content hash.
    pub hash: Hash,
}

/// Hash a tree (directory) structure.
///
/// Entries should be sorted by path for deterministic hashing.
pub fn hash_tree(entries: &[TreeEntry]) -> Hash {
    let mut hasher = blake3::Hasher::new();
    hasher.update(b"tree\x00");

    for entry in entries {
        // Mode as octal string
        let mode_str = format!("{:o}", entry.mode);
        hasher.update(mode_str.as_bytes());
        hasher.update(b" ");
        
        // Path
        hasher.update(entry.path.as_bytes());
        hasher.update(b"\x00");
        
        // Hash
        hasher.update(&entry.hash);
    }

    hasher.finalize().into()
}

/// Check if two hashes are equal in constant time.
///
/// This is useful for security-sensitive comparisons where
/// timing attacks might be a concern.
#[allow(dead_code)]
#[inline]
pub fn constant_time_eq(a: &Hash, b: &Hash) -> bool {
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_is_deterministic() {
        let data = b"Hello, World!";
        let h1 = hash(data);
        let h2 = hash(data);
        assert_eq!(h1, h2);
    }

    #[test]
    fn hash_is_different_for_different_input() {
        let h1 = hash(b"hello");
        let h2 = hash(b"Hello");
        assert_ne!(h1, h2);
    }

    #[test]
    fn hash_blob_includes_type_prefix() {
        let content = b"test content";
        let blob_hash = hash_blob(content);
        let raw_hash = hash(content);
        
        // Blob hash should be different from raw hash due to prefix
        assert_ne!(blob_hash, raw_hash);
    }

    #[test]
    fn hash_blob_is_deterministic() {
        let content = b"test content";
        let h1 = hash_blob(content);
        let h2 = hash_blob(content);
        assert_eq!(h1, h2);
    }

    #[test]
    fn hash_path_is_deterministic() {
        let path = "src/main.rs";
        let h1 = hash_path(path);
        let h2 = hash_path(path);
        assert_eq!(h1, h2);
    }

    #[test]
    fn format_hex_produces_correct_length() {
        let hash = hash(b"test");
        let hex = format_hex(&hash);
        assert_eq!(hex.len(), HASH_SIZE * 2);
    }

    #[test]
    fn format_hex_is_lowercase() {
        let hash = [0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56, 0x78, 0x90,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
        let hex = format_hex(&hash);
        assert!(hex.starts_with("abcdef12"));
    }

    #[test]
    fn parse_hex_roundtrip() {
        let original = hash(b"test data");
        let hex = format_hex(&original);
        let parsed = parse_hex(&hex).unwrap();
        assert_eq!(original, parsed);
    }

    #[test]
    fn parse_hex_rejects_invalid() {
        assert!(parse_hex("").is_none());
        assert!(parse_hex("not-hex").is_none());
        assert!(parse_hex("abc").is_none()); // too short
        
        // Wrong length
        let short = "a".repeat(62);
        assert!(parse_hex(&short).is_none());
        
        // Invalid characters
        let invalid = "g".repeat(64);
        assert!(parse_hex(&invalid).is_none());
    }

    #[test]
    fn parse_hex_accepts_uppercase() {
        let hex_lower = "a".repeat(64);
        let hex_upper = "A".repeat(64);
        
        let lower = parse_hex(&hex_lower).unwrap();
        let upper = parse_hex(&hex_upper).unwrap();
        
        assert_eq!(lower, upper);
    }

    #[test]
    fn constant_time_eq_works() {
        let a = hash(b"test");
        let b = hash(b"test");
        let c = hash(b"different");
        
        assert!(constant_time_eq(&a, &b));
        assert!(!constant_time_eq(&a, &c));
    }

    #[test]
    fn encode_length_handles_zero() {
        let encoded = encode_length(0);
        assert_eq!(encoded, vec![0]);
    }

    #[test]
    fn encode_length_handles_small_values() {
        let encoded = encode_length(127);
        assert_eq!(encoded, vec![127]);
    }

    #[test]
    fn encode_length_handles_large_values() {
        // 128 = 0x80, encoded as [0x00 | 0x80, 0x01] = [0x80, 0x01]
        let encoded = encode_length(128);
        assert_eq!(encoded.len(), 2);
    }
}
