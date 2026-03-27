//! Content cache for hif.
//!
#![allow(dead_code)]

//! Caches blob content locally to avoid repeated fetches from the forge.
//! Uses a simple disk-based LRU cache with content-addressed storage.

use crate::core::hash::{self, Hash};
use crate::error::Result;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::time::SystemTime;

/// Default maximum cache size in bytes (100 MB).
const DEFAULT_MAX_SIZE: u64 = 100 * 1024 * 1024;

/// Cache entry metadata.
#[derive(Debug, Clone)]
struct CacheEntry {
    /// Content hash
    hash: Hash,
    /// Size in bytes
    size: u64,
    /// Last access time
    accessed: SystemTime,
}

/// Content cache.
pub struct Cache {
    /// Cache directory
    dir: PathBuf,
    /// Maximum cache size
    max_size: u64,
    /// Current cache size
    current_size: u64,
    /// Cache entries (hash -> metadata)
    entries: HashMap<Hash, CacheEntry>,
}

impl Cache {
    /// Open or create a cache in the given directory.
    pub fn open(dir: PathBuf) -> Result<Self> {
        Self::open_with_size(dir, DEFAULT_MAX_SIZE)
    }

    /// Open or create a cache with a custom size limit.
    pub fn open_with_size(dir: PathBuf, max_size: u64) -> Result<Self> {
        // Create cache directory if needed
        if !dir.exists() {
            fs::create_dir_all(&dir)?;
        }

        let mut cache = Self {
            dir,
            max_size,
            current_size: 0,
            entries: HashMap::new(),
        };

        // Scan existing entries
        cache.scan_entries()?;

        Ok(cache)
    }

    /// Get content by hash.
    pub fn get(&mut self, hash: &Hash) -> Result<Option<Vec<u8>>> {
        // First check if entry exists and get the path
        let path = self.blob_path(hash);

        if !self.entries.contains_key(hash) {
            return Ok(None);
        }

        if path.exists() {
            // Update access time
            if let Some(entry) = self.entries.get_mut(hash) {
                entry.accessed = SystemTime::now();
            }

            let content = fs::read(&path)?;
            return Ok(Some(content));
        } else {
            // Entry exists but file is missing - clean up
            if let Some(entry) = self.entries.remove(hash) {
                self.current_size = self.current_size.saturating_sub(entry.size);
            }
        }

        Ok(None)
    }

    /// Put content in the cache.
    pub fn put(&mut self, content: &[u8]) -> Result<Hash> {
        let hash = hash::hash_blob(content);

        // Check if already cached
        if self.entries.contains_key(&hash) {
            // Update access time
            if let Some(entry) = self.entries.get_mut(&hash) {
                entry.accessed = SystemTime::now();
            }
            return Ok(hash);
        }

        let size = content.len() as u64;

        // Evict if needed
        while self.current_size + size > self.max_size && !self.entries.is_empty() {
            self.evict_oldest()?;
        }

        // Write to disk
        let path = self.blob_path(&hash);

        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent)?;
            }
        }

        fs::write(&path, content)?;

        // Add entry
        self.entries.insert(
            hash,
            CacheEntry {
                hash,
                size,
                accessed: SystemTime::now(),
            },
        );
        self.current_size += size;

        Ok(hash)
    }

    /// Check if content is cached.
    pub fn contains(&self, hash: &Hash) -> bool {
        self.entries.contains_key(hash)
    }

    /// Remove content from cache.
    pub fn remove(&mut self, hash: &Hash) -> Result<bool> {
        if let Some(entry) = self.entries.remove(hash) {
            let path = self.blob_path(hash);
            if path.exists() {
                fs::remove_file(&path)?;
            }
            self.current_size = self.current_size.saturating_sub(entry.size);
            return Ok(true);
        }
        Ok(false)
    }

    /// Clear the entire cache.
    pub fn clear(&mut self) -> Result<()> {
        // Remove all blob files
        let blobs_dir = self.dir.join("blobs");
        if blobs_dir.exists() {
            fs::remove_dir_all(&blobs_dir)?;
            fs::create_dir_all(&blobs_dir)?;
        }

        self.entries.clear();
        self.current_size = 0;

        Ok(())
    }

    /// Get cache statistics.
    pub fn stats(&self) -> CacheStats {
        CacheStats {
            entries: self.entries.len(),
            current_size: self.current_size,
            max_size: self.max_size,
        }
    }

    /// Scan existing entries in the cache directory.
    fn scan_entries(&mut self) -> Result<()> {
        let blobs_dir = self.dir.join("blobs");
        if !blobs_dir.exists() {
            return Ok(());
        }

        for prefix_entry in fs::read_dir(&blobs_dir)? {
            let prefix_entry = prefix_entry?;
            if !prefix_entry.file_type()?.is_dir() {
                continue;
            }

            for blob_entry in fs::read_dir(prefix_entry.path())? {
                let blob_entry = blob_entry?;
                let path = blob_entry.path();

                if let Some(name) = path.file_name() {
                    if let Some(name_str) = name.to_str() {
                        if let Some(hash) = hash::parse_hex(name_str) {
                            let metadata = fs::metadata(&path)?;
                            let size = metadata.len();
                            let accessed =
                                metadata.accessed().unwrap_or_else(|_| SystemTime::now());

                            self.entries.insert(
                                hash,
                                CacheEntry {
                                    hash,
                                    size,
                                    accessed,
                                },
                            );
                            self.current_size += size;
                        }
                    }
                }
            }
        }

        Ok(())
    }

    /// Get the path for a blob.
    fn blob_path(&self, hash: &Hash) -> PathBuf {
        let hex = hash::format_hex(hash);
        let prefix = &hex[0..2];
        self.dir.join("blobs").join(prefix).join(&hex)
    }

    /// Evict the oldest entry.
    fn evict_oldest(&mut self) -> Result<()> {
        let oldest = self
            .entries
            .values()
            .min_by_key(|e| e.accessed)
            .map(|e| e.hash);

        if let Some(hash) = oldest {
            self.remove(&hash)?;
        }

        Ok(())
    }
}

/// Cache statistics.
#[derive(Debug, Clone)]
pub struct CacheStats {
    /// Number of entries
    pub entries: usize,
    /// Current size in bytes
    pub current_size: u64,
    /// Maximum size in bytes
    pub max_size: u64,
}

impl CacheStats {
    /// Get the fill ratio (0.0 to 1.0).
    pub fn fill_ratio(&self) -> f64 {
        if self.max_size == 0 {
            return 0.0;
        }
        self.current_size as f64 / self.max_size as f64
    }
}

/// Get the default cache directory.
pub fn default_cache_dir() -> Result<PathBuf> {
    let config_dir = crate::config::config_dir()?;
    Ok(config_dir.join("cache"))
}

/// Open the default cache.
pub fn open_default_cache() -> Result<Cache> {
    Cache::open(default_cache_dir()?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn cache_put_and_get() {
        let dir = tempdir().unwrap();
        let mut cache = Cache::open(dir.path().to_path_buf()).unwrap();

        let content = b"Hello, World!";
        let hash = cache.put(content).unwrap();

        let retrieved = cache.get(&hash).unwrap().unwrap();
        assert_eq!(retrieved, content);
    }

    #[test]
    fn cache_deduplication() {
        let dir = tempdir().unwrap();
        let mut cache = Cache::open(dir.path().to_path_buf()).unwrap();

        let content = b"Same content";
        let hash1 = cache.put(content).unwrap();
        let hash2 = cache.put(content).unwrap();

        assert_eq!(hash1, hash2);
        assert_eq!(cache.stats().entries, 1);
    }

    #[test]
    fn cache_eviction() {
        let dir = tempdir().unwrap();
        let mut cache = Cache::open_with_size(dir.path().to_path_buf(), 100).unwrap();

        // Put entries that exceed max size
        for i in 0..20 {
            let content = format!("Content {}", i);
            cache.put(content.as_bytes()).unwrap();
        }

        // Cache should have evicted old entries
        assert!(cache.stats().current_size <= 100);
    }

    #[test]
    fn cache_remove() {
        let dir = tempdir().unwrap();
        let mut cache = Cache::open(dir.path().to_path_buf()).unwrap();

        let content = b"To be removed";
        let hash = cache.put(content).unwrap();

        assert!(cache.contains(&hash));
        cache.remove(&hash).unwrap();
        assert!(!cache.contains(&hash));
    }

    #[test]
    fn cache_clear() {
        let dir = tempdir().unwrap();
        let mut cache = Cache::open(dir.path().to_path_buf()).unwrap();

        cache.put(b"Content 1").unwrap();
        cache.put(b"Content 2").unwrap();

        assert_eq!(cache.stats().entries, 2);

        cache.clear().unwrap();

        assert_eq!(cache.stats().entries, 0);
        assert_eq!(cache.stats().current_size, 0);
    }

    #[test]
    fn cache_persistence() {
        let dir = tempdir().unwrap();
        let hash;

        // Create cache and add content
        {
            let mut cache = Cache::open(dir.path().to_path_buf()).unwrap();
            hash = cache.put(b"Persistent content").unwrap();
        }

        // Reopen cache and verify content is still there
        {
            let mut cache = Cache::open(dir.path().to_path_buf()).unwrap();
            assert!(cache.contains(&hash));
            let content = cache.get(&hash).unwrap().unwrap();
            assert_eq!(content, b"Persistent content");
        }
    }
}
