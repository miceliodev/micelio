//! Workspace manifest management.
//!
//! The manifest stores the workspace state including server, project,
//! and file entries.
#![allow(dead_code)]

use crate::error::{MicError, Result};
use crate::workspace::{ensure_hif_dir, hif_dir, HIF_DIR, MANIFEST_FILE};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

/// Simplified manifest for reading project info.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Server URL.
    pub server: String,
    /// Organization handle.
    pub organization: String,
    /// Project handle.
    pub project: String,
}

impl Manifest {
    /// Create a new manifest.
    pub fn new(server: &str, organization: &str, project: &str) -> Self {
        Self {
            server: server.to_string(),
            organization: organization.to_string(),
            project: project.to_string(),
        }
    }

    /// Find and load the manifest by searching up the directory tree.
    pub fn find_and_load() -> Result<Self> {
        let mut current = std::env::current_dir()?;

        loop {
            let manifest_path = current.join(HIF_DIR).join(MANIFEST_FILE);
            if manifest_path.exists() {
                let data = fs::read_to_string(&manifest_path)?;
                let workspace: WorkspaceManifest = serde_json::from_str(&data).map_err(|e| {
                    MicError::ConfigError(format!("failed to parse manifest: {}", e))
                })?;

                return Ok(Self {
                    server: workspace.server,
                    organization: workspace.account,
                    project: workspace.project,
                });
            }

            match current.parent() {
                Some(parent) => current = parent.to_path_buf(),
                None => return Err(MicError::NoWorkspace),
            }
        }
    }

    /// Save the manifest to the current directory.
    pub fn save(&self) -> Result<()> {
        let workspace = WorkspaceManifest::new(&self.server, &self.organization, &self.project);
        workspace.save()
    }

    /// Get the full project reference (org/project).
    pub fn project_ref(&self) -> String {
        format!("{}/{}", self.organization, self.project)
    }
}

/// Workspace manifest containing project link and state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceManifest {
    /// Manifest version.
    pub version: u32,
    /// Server URL.
    pub server: String,
    /// Account/organization handle.
    pub account: String,
    /// Project handle.
    pub project: String,
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
    pub fn new(server: &str, account: &str, project: &str) -> Self {
        Self {
            version: 1,
            server: server.to_string(),
            account: account.to_string(),
            project: project.to_string(),
            tree_hash: String::new(),
            entries: Vec::new(),
        }
    }

    /// Load workspace manifest from the current directory.
    pub fn load() -> Result<Option<Self>> {
        let path = hif_dir()?.join(MANIFEST_FILE);
        Self::load_from(&path)
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

    /// Get the full project reference (account/project).
    pub fn project_ref(&self) -> String {
        format!("{}/{}", self.account, self.project)
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
        assert_eq!(manifest.project, "app");
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
        assert_eq!(loaded.project, manifest.project);
        assert_eq!(loaded.tree_hash, manifest.tree_hash);
        assert_eq!(loaded.entries.len(), 1);
        assert_eq!(loaded.entries[0].path, "README.md");
    }

    #[test]
    fn manifest_project_ref() {
        let manifest = WorkspaceManifest::new("http://localhost:50051", "acme", "app");

        assert_eq!(manifest.project_ref(), "acme/app");
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
