//! Workspace manifest management.
//!
//! The manifest stores the workspace state including server, repository,
//! and file entries.
#![allow(dead_code)]

use crate::error::{MicError, Result};
use crate::workspace::{
    ensure_hif_dir, find_workspace_root_from, hif_dir, metadata_dir_for_root, workspace_root,
    MANIFEST_FILE,
};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

/// Simplified manifest for reading repository info.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Server URL.
    pub server: String,
    /// Organization handle.
    pub organization: String,
    /// Repository handle.
    pub repository: String,
}

impl Manifest {
    /// Create a new manifest.
    pub fn new(server: &str, organization: &str, repository: &str) -> Self {
        Self {
            server: server.to_string(),
            organization: organization.to_string(),
            repository: repository.to_string(),
        }
    }

    /// Find and load the manifest by searching up the directory tree.
    pub fn find_and_load() -> Result<Self> {
        let current = std::env::current_dir()?;
        let workspace_root = find_workspace_root_from(&current).ok_or(MicError::NoWorkspace)?;
        let manifest_path = metadata_dir_for_root(&workspace_root).join(MANIFEST_FILE);
        let data = fs::read_to_string(&manifest_path)?;
        let workspace: WorkspaceManifest = serde_json::from_str(&data)
            .map_err(|e| MicError::ConfigError(format!("failed to parse manifest: {}", e)))?;

        Ok(Self {
            server: workspace.server,
            organization: workspace.account,
            repository: workspace.repository,
        })
    }

    /// Save the manifest to the current directory.
    pub fn save(&self) -> Result<()> {
        let workspace = WorkspaceManifest::new(&self.server, &self.organization, &self.repository);
        workspace.save()
    }

    /// Get the full repository reference (account/repository).
    pub fn repository_ref(&self) -> String {
        format!("{}/{}", self.organization, self.repository)
    }
}

/// Workspace manifest containing repository link and state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceManifest {
    /// Manifest version.
    pub version: u32,
    /// Server URL.
    pub server: String,
    /// Account/organization handle.
    pub account: String,
    /// Repository handle.
    pub repository: String,
    /// Current tree hash.
    pub tree_hash: String,
    /// File entries.
    #[serde(default)]
    pub entries: Vec<WorkspaceEntry>,
}

/// A file entry in the workspace.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceEntry {
    /// File path relative to workspace root.
    pub path: String,
    /// File content hash.
    pub hash: String,
    /// File mode (permissions).
    pub mode: u32,
    /// File size in bytes.
    pub size: u64,
}

impl WorkspaceManifest {
    /// Create a new workspace manifest.
    pub fn new(server: &str, account: &str, repository: &str) -> Self {
        Self {
            version: 1,
            server: server.to_string(),
            account: account.to_string(),
            repository: repository.to_string(),
            tree_hash: String::new(),
            entries: Vec::new(),
        }
    }

    /// Load workspace manifest from the current directory.
    pub fn load() -> Result<Option<Self>> {
        match workspace_root() {
            Ok(root) => Self::load_from(&metadata_dir_for_root(&root).join(MANIFEST_FILE)),
            Err(MicError::NoWorkspace) => Ok(None),
            Err(error) => Err(error),
        }
    }

    /// Load workspace manifest from a specific path.
    pub fn load_from(path: &Path) -> Result<Option<Self>> {
        if !path.exists() {
            return Ok(None);
        }

        let data = fs::read_to_string(path)?;
        let manifest: Self = serde_json::from_str(&data)
            .map_err(|e| MicError::ConfigError(format!("failed to parse manifest: {}", e)))?;

        Ok(Some(manifest))
    }

    /// Save workspace manifest to the current directory.
    pub fn save(&self) -> Result<()> {
        ensure_hif_dir()?;
        let path = hif_dir()?.join(MANIFEST_FILE);
        self.save_to(&path)
    }

    /// Save workspace manifest to a specific path.
    pub fn save_to(&self, path: &Path) -> Result<()> {
        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent)?;
            }
        }

        let data = serde_json::to_string_pretty(self)
            .map_err(|e| MicError::ConfigError(format!("failed to serialize manifest: {}", e)))?;

        fs::write(path, data)?;
        Ok(())
    }

    /// Get the full repository reference (account/repository).
    pub fn repository_ref(&self) -> String {
        format!("{}/{}", self.account, self.repository)
    }

    /// Find an entry by path.
    pub fn find_entry(&self, path: &str) -> Option<&WorkspaceEntry> {
        self.entries.iter().find(|e| e.path == path)
    }

    /// Update or add an entry.
    pub fn upsert_entry(&mut self, entry: WorkspaceEntry) {
        if let Some(existing) = self.entries.iter_mut().find(|e| e.path == entry.path) {
            *existing = entry;
        } else {
            self.entries.push(entry);
        }
    }

    /// Remove an entry by path.
    pub fn remove_entry(&mut self, path: &str) -> bool {
        let len_before = self.entries.len();
        self.entries.retain(|e| e.path != path);
        self.entries.len() < len_before
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn manifest_new() {
        let manifest = WorkspaceManifest::new("http://localhost:50051", "acme", "app");

        assert_eq!(manifest.version, 1);
        assert_eq!(manifest.server, "http://localhost:50051");
        assert_eq!(manifest.account, "acme");
        assert_eq!(manifest.repository, "app");
        assert!(manifest.entries.is_empty());
    }

    #[test]
    fn manifest_save_and_load() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("manifest.json");

        let mut manifest = WorkspaceManifest::new("http://localhost:50051", "acme", "app");
        manifest.tree_hash = "deadbeef".to_string();
        manifest.entries.push(WorkspaceEntry {
            path: "README.md".to_string(),
            hash: "abc123".to_string(),
            mode: 0o100644,
            size: 100,
        });

        manifest.save_to(&path).unwrap();

        let loaded = WorkspaceManifest::load_from(&path).unwrap().unwrap();

        assert_eq!(loaded.server, manifest.server);
        assert_eq!(loaded.account, manifest.account);
        assert_eq!(loaded.repository, manifest.repository);
        assert_eq!(loaded.tree_hash, manifest.tree_hash);
        assert_eq!(loaded.entries.len(), 1);
        assert_eq!(loaded.entries[0].path, "README.md");
    }

    #[test]
    fn manifest_repository_ref() {
        let manifest = WorkspaceManifest::new("http://localhost:50051", "acme", "app");

        assert_eq!(manifest.repository_ref(), "acme/app");
    }

    #[test]
    fn manifest_entry_operations() {
        let mut manifest = WorkspaceManifest::new("http://localhost:50051", "acme", "app");

        // Add entry
        manifest.upsert_entry(WorkspaceEntry {
            path: "README.md".to_string(),
            hash: "hash1".to_string(),
            mode: 0o100644,
            size: 100,
        });

        assert_eq!(manifest.entries.len(), 1);
        assert_eq!(manifest.find_entry("README.md").unwrap().hash, "hash1");

        // Update entry
        manifest.upsert_entry(WorkspaceEntry {
            path: "README.md".to_string(),
            hash: "hash2".to_string(),
            mode: 0o100644,
            size: 200,
        });

        assert_eq!(manifest.entries.len(), 1);
        assert_eq!(manifest.find_entry("README.md").unwrap().hash, "hash2");

        // Remove entry
        assert!(manifest.remove_entry("README.md"));
        assert!(!manifest.remove_entry("README.md")); // Already removed
        assert!(manifest.entries.is_empty());
    }
}
