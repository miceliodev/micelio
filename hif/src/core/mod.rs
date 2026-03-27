//! Core algorithms for hif.
//!
//! This module provides the fundamental data structures and algorithms
//! used by the hif version control system:
//!
//! - [`hash`]: Blake3 hashing for content-addressed storage
//! - [`bloom`]: Bloom filters for fast path conflict detection  
//! - [`hlc`]: Hybrid Logical Clocks for distributed timestamps
//! - [`tree`]: B+ trees for directory structures
//!
//! # Example
//!
//! ```
//! use hif::core::{Bloom, hash};
//!
//! // Hash some content
//! let hash = hash::hash_blob(b"Hello, World!");
//! let hex = hash::format_hex(&hash);
//!
//! // Track paths in a bloom filter
//! let mut bloom = Bloom::new(100, 0.01).unwrap();
//! bloom.add("src/main.rs");
//! ```

pub mod bloom;
pub mod hash;
pub mod hlc;
pub mod tree;

// Re-export commonly used types
pub use bloom::Bloom;

#[allow(unused_imports)]
pub use hash::Hash;
