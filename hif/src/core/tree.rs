//! B+ tree for directory structures.
//!
//! This implements a content-addressed B+ tree for storing file system trees.
//! Each node is identified by its content hash, enabling efficient storage
//! and comparison of tree states.
#![allow(dead_code)]

use super::hash::{self, Hash, HASH_SIZE};
use std::collections::BTreeMap;

/// Maximum number of entries per node.
const MAX_ENTRIES: usize = 64;

/// Minimum entries for a non-root node.
const MIN_ENTRIES: usize = MAX_ENTRIES / 2;

/// Tree entry type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EntryType {
    /// Regular file
    File,
    /// Directory (subtree)
    Directory,
    /// Symbolic link
    Symlink,
}

impl EntryType {
    pub fn from_mode(mode: u32) -> Self {
        match mode & 0o170000 {
            0o040000 => EntryType::Directory,
            0o120000 => EntryType::Symlink,
            _ => EntryType::File,
        }
    }

    pub fn to_mode(self) -> u32 {
        match self {
            EntryType::File => 0o100644,
            EntryType::Directory => 0o040000,
            EntryType::Symlink => 0o120000,
        }
    }
}

/// A tree entry.
#[derive(Debug, Clone)]
pub struct TreeEntry {
    /// Entry name (file/directory name, not full path)
    pub name: String,
    /// Entry type
    pub entry_type: EntryType,
    /// File mode (permissions)
    pub mode: u32,
    /// Content hash (blob hash for files, tree hash for directories)
    pub hash: Hash,
    /// File size (0 for directories)
    pub size: u64,
}

impl TreeEntry {
    /// Create a new file entry.
    pub fn file(name: &str, hash: Hash, size: u64, mode: u32) -> Self {
        Self {
            name: name.to_string(),
            entry_type: EntryType::File,
            mode: mode | 0o100000,
            hash,
            size,
        }
    }

    /// Create a new directory entry.
    pub fn directory(name: &str, hash: Hash) -> Self {
        Self {
            name: name.to_string(),
            entry_type: EntryType::Directory,
            mode: 0o040000,
            hash,
            size: 0,
        }
    }

    /// Create a new symlink entry.
    pub fn symlink(name: &str, hash: Hash) -> Self {
        Self {
            name: name.to_string(),
            entry_type: EntryType::Symlink,
            mode: 0o120000,
            hash,
            size: 0,
        }
    }
}

/// A tree node in the B+ tree.
#[derive(Debug, Clone)]
pub struct TreeNode {
    /// Entries sorted by name
    pub entries: BTreeMap<String, TreeEntry>,
}

impl TreeNode {
    /// Create an empty tree node.
    pub fn new() -> Self {
        Self {
            entries: BTreeMap::new(),
        }
    }

    /// Create a tree node from entries.
    pub fn from_entries(entries: Vec<TreeEntry>) -> Self {
        let mut node = Self::new();
        for entry in entries {
            node.entries.insert(entry.name.clone(), entry);
        }
        node
    }

    /// Insert an entry.
    pub fn insert(&mut self, entry: TreeEntry) {
        self.entries.insert(entry.name.clone(), entry);
    }

    /// Remove an entry by name.
    pub fn remove(&mut self, name: &str) -> Option<TreeEntry> {
        self.entries.remove(name)
    }

    /// Get an entry by name.
    pub fn get(&self, name: &str) -> Option<&TreeEntry> {
        self.entries.get(name)
    }

    /// Check if empty.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Number of entries.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Compute the hash of this tree node.
    pub fn hash(&self) -> Hash {
        let entries: Vec<hash::TreeEntry> = self
            .entries
            .values()
            .map(|e| hash::TreeEntry {
                mode: e.mode,
                path: &e.name,
                hash: e.hash,
            })
            .collect();

        hash::hash_tree(&entries)
    }

    /// Serialize the tree node to bytes.
    pub fn serialize(&self) -> Vec<u8> {
        let mut buf = Vec::new();

        // Write number of entries
        write_varint(&mut buf, self.entries.len() as u64);

        for entry in self.entries.values() {
            // Name (length-prefixed)
            write_varint(&mut buf, entry.name.len() as u64);
            buf.extend_from_slice(entry.name.as_bytes());

            // Mode (4 bytes)
            buf.extend_from_slice(&entry.mode.to_le_bytes());

            // Hash (32 bytes)
            buf.extend_from_slice(&entry.hash);

            // Size (8 bytes)
            buf.extend_from_slice(&entry.size.to_le_bytes());
        }

        buf
    }

    /// Deserialize a tree node from bytes.
    pub fn deserialize(data: &[u8]) -> Option<Self> {
        let mut pos = 0;
        let count = read_varint(data, &mut pos)? as usize;

        let mut entries = BTreeMap::new();

        for _ in 0..count {
            // Name
            let name_len = read_varint(data, &mut pos)? as usize;
            if pos + name_len > data.len() {
                return None;
            }
            let name = String::from_utf8_lossy(&data[pos..pos + name_len]).to_string();
            pos += name_len;

            // Mode
            if pos + 4 > data.len() {
                return None;
            }
            let mode = u32::from_le_bytes(data[pos..pos + 4].try_into().ok()?);
            pos += 4;

            // Hash
            if pos + HASH_SIZE > data.len() {
                return None;
            }
            let mut hash = [0u8; HASH_SIZE];
            hash.copy_from_slice(&data[pos..pos + HASH_SIZE]);
            pos += HASH_SIZE;

            // Size
            if pos + 8 > data.len() {
                return None;
            }
            let size = u64::from_le_bytes(data[pos..pos + 8].try_into().ok()?);
            pos += 8;

            let entry_type = EntryType::from_mode(mode);
            entries.insert(
                name.clone(),
                TreeEntry {
                    name,
                    entry_type,
                    mode,
                    hash,
                    size,
                },
            );
        }

        Some(Self { entries })
    }
}

impl Default for TreeNode {
    fn default() -> Self {
        Self::new()
    }
}

/// A complete tree with path-based access.
#[derive(Debug, Clone)]
pub struct Tree {
    /// Root node
    root: TreeNode,
}

impl Tree {
    /// Create an empty tree.
    pub fn new() -> Self {
        Self {
            root: TreeNode::new(),
        }
    }

    /// Create a tree from a root node.
    pub fn from_root(root: TreeNode) -> Self {
        Self { root }
    }

    /// Get the root node.
    pub fn root(&self) -> &TreeNode {
        &self.root
    }

    /// Get a mutable reference to the root node.
    pub fn root_mut(&mut self) -> &mut TreeNode {
        &mut self.root
    }

    /// Insert a file at a path.
    pub fn insert_file(&mut self, path: &str, hash: Hash, size: u64, mode: u32) {
        let parts: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        if parts.is_empty() {
            return;
        }

        let name = parts.last().unwrap();
        let entry = TreeEntry::file(name, hash, size, mode);
        self.root.insert(entry);
    }

    /// Remove a file at a path.
    pub fn remove(&mut self, path: &str) -> Option<TreeEntry> {
        let parts: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        if parts.is_empty() {
            return None;
        }

        let name = parts.last().unwrap();
        self.root.remove(name)
    }

    /// Get a file entry by path.
    pub fn get(&self, path: &str) -> Option<&TreeEntry> {
        let parts: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        if parts.is_empty() {
            return None;
        }

        let name = parts.last().unwrap();
        self.root.get(name)
    }

    /// List all entries.
    pub fn list(&self) -> Vec<&TreeEntry> {
        self.root.entries.values().collect()
    }

    /// Compute the tree hash.
    pub fn hash(&self) -> Hash {
        self.root.hash()
    }

    /// Check if empty.
    pub fn is_empty(&self) -> bool {
        self.root.is_empty()
    }

    /// Number of entries.
    pub fn len(&self) -> usize {
        self.root.len()
    }
}

impl Default for Tree {
    fn default() -> Self {
        Self::new()
    }
}

/// Write a varint to a buffer.
fn write_varint(buf: &mut Vec<u8>, mut value: u64) {
    while value >= 0x80 {
        buf.push((value as u8 & 0x7f) | 0x80);
        value >>= 7;
    }
    buf.push(value as u8);
}

/// Read a varint from a buffer.
fn read_varint(data: &[u8], pos: &mut usize) -> Option<u64> {
    let mut value: u64 = 0;
    let mut shift = 0;

    while *pos < data.len() {
        let byte = data[*pos];
        *pos += 1;

        value |= ((byte & 0x7f) as u64) << shift;

        if (byte & 0x80) == 0 {
            return Some(value);
        }

        shift += 7;
        if shift >= 64 {
            return None;
        }
    }

    None
}

/// Compute the difference between two trees.
pub fn diff(old: &Tree, new: &Tree) -> TreeDiff {
    let mut added = Vec::new();
    let mut modified = Vec::new();
    let mut deleted = Vec::new();

    // Find added and modified
    for (name, new_entry) in &new.root.entries {
        match old.root.entries.get(name) {
            None => added.push(new_entry.clone()),
            Some(old_entry) => {
                if old_entry.hash != new_entry.hash {
                    modified.push(new_entry.clone());
                }
            }
        }
    }

    // Find deleted
    for (name, old_entry) in &old.root.entries {
        if !new.root.entries.contains_key(name) {
            deleted.push(old_entry.clone());
        }
    }

    TreeDiff {
        added,
        modified,
        deleted,
    }
}

/// Difference between two trees.
#[derive(Debug, Clone)]
pub struct TreeDiff {
    /// Added entries
    pub added: Vec<TreeEntry>,
    /// Modified entries
    pub modified: Vec<TreeEntry>,
    /// Deleted entries
    pub deleted: Vec<TreeEntry>,
}

impl TreeDiff {
    /// Check if there are any changes.
    pub fn is_empty(&self) -> bool {
        self.added.is_empty() && self.modified.is_empty() && self.deleted.is_empty()
    }

    /// Total number of changes.
    pub fn len(&self) -> usize {
        self.added.len() + self.modified.len() + self.deleted.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tree_node_insert_and_get() {
        let mut node = TreeNode::new();
        let hash = hash::hash(b"content");

        node.insert(TreeEntry::file("test.txt", hash, 100, 0o644));

        let entry = node.get("test.txt").unwrap();
        assert_eq!(entry.name, "test.txt");
        assert_eq!(entry.size, 100);
        assert_eq!(entry.hash, hash);
    }

    #[test]
    fn tree_node_serialize_deserialize() {
        let mut node = TreeNode::new();
        let hash1 = hash::hash(b"content1");
        let hash2 = hash::hash(b"content2");

        node.insert(TreeEntry::file("a.txt", hash1, 100, 0o644));
        node.insert(TreeEntry::file("b.txt", hash2, 200, 0o755));

        let serialized = node.serialize();
        let restored = TreeNode::deserialize(&serialized).unwrap();

        assert_eq!(restored.len(), 2);
        assert_eq!(restored.get("a.txt").unwrap().size, 100);
        assert_eq!(restored.get("b.txt").unwrap().size, 200);
    }

    #[test]
    fn tree_node_hash_is_deterministic() {
        let mut node1 = TreeNode::new();
        let mut node2 = TreeNode::new();
        let hash = hash::hash(b"content");

        node1.insert(TreeEntry::file("test.txt", hash, 100, 0o644));
        node2.insert(TreeEntry::file("test.txt", hash, 100, 0o644));

        assert_eq!(node1.hash(), node2.hash());
    }

    #[test]
    fn tree_diff_detects_changes() {
        let hash1 = hash::hash(b"content1");
        let hash2 = hash::hash(b"content2");
        let hash3 = hash::hash(b"content3");

        let mut old = Tree::new();
        old.root_mut()
            .insert(TreeEntry::file("a.txt", hash1, 100, 0o644));
        old.root_mut()
            .insert(TreeEntry::file("b.txt", hash2, 200, 0o644));

        let mut new = Tree::new();
        new.root_mut()
            .insert(TreeEntry::file("a.txt", hash1, 100, 0o644)); // unchanged
        new.root_mut()
            .insert(TreeEntry::file("b.txt", hash3, 200, 0o644)); // modified
        new.root_mut()
            .insert(TreeEntry::file("c.txt", hash2, 300, 0o644)); // added

        let diff = diff(&old, &new);

        assert_eq!(diff.added.len(), 1);
        assert_eq!(diff.modified.len(), 1);
        assert_eq!(diff.deleted.len(), 0);

        assert_eq!(diff.added[0].name, "c.txt");
        assert_eq!(diff.modified[0].name, "b.txt");
    }
}
