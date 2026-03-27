//! Workspace change detection.
//!
//! Detects changes between the workspace manifest and the actual files on disk.
#![allow(dead_code)]

use crate::error::Result;
use crate::workspace::{is_safe_path, is_workspace_metadata_path, WorkspaceManifest};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

/// A detected change in the workspace.
#[derive(Debug, Clone)]
pub struct WorkspaceChange {
    /// File path relative to workspace root
    pub path: String,
    /// Type of change
    pub change_type: ChangeType,
}

/// Type of change.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChangeType {
    Added,
    Modified,
    Deleted,
}

impl ChangeType {
    /// Get the single-character prefix for display.
    pub fn prefix(&self) -> &'static str {
        match self {
            ChangeType::Added => "A",
            ChangeType::Modified => "M",
            ChangeType::Deleted => "D",
        }
    }

    /// Get the string name.
    pub fn as_str(&self) -> &'static str {
        match self {
            ChangeType::Added => "added",
            ChangeType::Modified => "modified",
            ChangeType::Deleted => "deleted",
        }
    }
}

/// Collect all changes in the workspace.
pub fn collect_changes(
    workspace_root: &Path,
    manifest: &WorkspaceManifest,
) -> Result<Vec<WorkspaceChange>> {
    let mut changes = Vec::new();

    // Build a map of known files from manifest
    let mut known_files: HashMap<String, String> = manifest
        .entries
        .iter()
        .map(|e| (e.path.clone(), e.hash.clone()))
        .collect();

    // Scan the workspace for files
    let ignore = load_ignore_patterns(workspace_root);
    let files = scan_files(workspace_root, &ignore)?;

    // Check for added and modified files
    for file_path in &files {
        let relative = file_path
            .strip_prefix(workspace_root)
            .unwrap_or(file_path)
            .to_string_lossy()
            .to_string();

        if !is_safe_path(&relative) {
            continue;
        }

        if is_workspace_metadata_path(&relative) {
            continue;
        }

        if let Some(known_hash) = known_files.remove(&relative) {
            // File exists in manifest - check if modified
            let content = fs::read(file_path)?;
            let current_hash = micelio_blob_hash_hex(&content);

            if current_hash != known_hash {
                changes.push(WorkspaceChange {
                    path: relative,
                    change_type: ChangeType::Modified,
                });
            }
        } else {
            // New file
            changes.push(WorkspaceChange {
                path: relative,
                change_type: ChangeType::Added,
            });
        }
    }

    // Remaining files in known_files are deleted
    for path in known_files.keys() {
        changes.push(WorkspaceChange {
            path: path.clone(),
            change_type: ChangeType::Deleted,
        });
    }

    // Sort by path
    changes.sort_by(|a, b| a.path.cmp(&b.path));

    Ok(changes)
}

/// Scan files in the workspace.
fn scan_files(root: &Path, ignore: &IgnorePatterns) -> Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    scan_dir(root, root, ignore, &mut files)?;
    Ok(files)
}

/// Recursively scan a directory.
fn scan_dir(
    root: &Path,
    dir: &Path,
    ignore: &IgnorePatterns,
    files: &mut Vec<PathBuf>,
) -> Result<()> {
    if !dir.is_dir() {
        return Ok(());
    }

    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let relative = path
            .strip_prefix(root)
            .unwrap_or(&path)
            .to_string_lossy()
            .to_string();

        // Skip ignored files
        if ignore.is_ignored(&relative) {
            continue;
        }

        if path.is_dir() {
            // Skip .hif and .git directories
            let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
            if name == ".hif" || name == ".git" || name == "node_modules" {
                continue;
            }
            scan_dir(root, &path, ignore, files)?;
        } else {
            files.push(path);
        }
    }

    Ok(())
}

/// Ignore patterns for workspace scanning.
#[derive(Debug, Default)]
pub struct IgnorePatterns {
    patterns: Vec<String>,
}

impl IgnorePatterns {
    /// Create with default patterns.
    pub fn new() -> Self {
        Self {
            patterns: vec![
                ".hif".to_string(),
                ".hif/".to_string(),
                ".git".to_string(),
                ".git/".to_string(),
                "node_modules".to_string(),
                "node_modules/".to_string(),
                ".DS_Store".to_string(),
                "._*".to_string(),
                "*.swp".to_string(),
                "*~".to_string(),
            ],
        }
    }

    /// Add a pattern.
    pub fn add(&mut self, pattern: &str) {
        self.patterns.push(pattern.to_string());
    }

    /// Check if a path is ignored.
    pub fn is_ignored(&self, path: &str) -> bool {
        for pattern in &self.patterns {
            if matches_pattern(path, pattern) {
                return true;
            }
        }
        false
    }
}

/// Simple pattern matching.
fn matches_pattern(path: &str, pattern: &str) -> bool {
    // Exact match
    if path == pattern {
        return true;
    }

    // Directory prefix match
    if pattern.ends_with('/') {
        let prefix = &pattern[..pattern.len() - 1];
        if path == prefix || path.starts_with(pattern) {
            return true;
        }
    }

    // Glob pattern with *
    if pattern.ends_with('*') {
        let prefix = &pattern[..pattern.len() - 1];
        if path.starts_with(prefix)
            || path
                .split('/')
                .any(|component| component.starts_with(prefix))
        {
            return true;
        }
    }

    if pattern.starts_with('*') {
        let suffix = &pattern[1..];
        if path.ends_with(suffix) {
            return true;
        }
    }

    // Check if any path component matches
    for component in path.split('/') {
        if component == pattern {
            return true;
        }
    }

    false
}

/// Load ignore patterns from .hifignore file.
fn load_ignore_patterns(workspace_root: &Path) -> IgnorePatterns {
    let mut patterns = IgnorePatterns::new();

    let ignore_file = workspace_root.join(".hifignore");
    if let Ok(content) = fs::read_to_string(&ignore_file) {
        for line in content.lines() {
            let line = line.trim();
            // Skip empty lines and comments
            if !line.is_empty() && !line.starts_with('#') {
                patterns.add(line);
            }
        }
    }

    patterns
}

fn micelio_blob_hash_hex(content: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content);
    format!("{:x}", hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_change_type_prefix() {
        assert_eq!(ChangeType::Added.prefix(), "A");
        assert_eq!(ChangeType::Modified.prefix(), "M");
        assert_eq!(ChangeType::Deleted.prefix(), "D");
    }

    #[test]
    fn test_ignore_patterns() {
        let ignore = IgnorePatterns::new();

        assert!(ignore.is_ignored(".hif"));
        assert!(ignore.is_ignored(".hif/session.bin"));
        assert!(ignore.is_ignored(".git"));
        assert!(ignore.is_ignored("node_modules"));
        assert!(ignore.is_ignored("test.swp"));
        assert!(ignore.is_ignored("src/._main.rs"));

        assert!(!ignore.is_ignored("src/main.rs"));
        assert!(!ignore.is_ignored("README.md"));
    }

    #[test]
    fn test_matches_pattern() {
        assert!(matches_pattern(".git", ".git"));
        assert!(matches_pattern(".git/config", ".git/"));
        assert!(matches_pattern("test.swp", "*.swp"));
        assert!(matches_pattern("path/to/.DS_Store", ".DS_Store"));
        assert!(matches_pattern("src/._main.rs", "._*"));

        assert!(!matches_pattern("src/main.rs", ".git"));
        assert!(!matches_pattern("test.txt", "*.swp"));
    }

    #[test]
    fn test_scan_empty_dir() {
        let dir = tempdir().unwrap();
        let ignore = IgnorePatterns::new();
        let files = scan_files(dir.path(), &ignore).unwrap();
        assert!(files.is_empty());
    }

    #[test]
    fn test_scan_with_files() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join("file.txt"), "content").unwrap();
        fs::create_dir(dir.path().join("subdir")).unwrap();
        fs::write(dir.path().join("subdir/nested.txt"), "nested").unwrap();

        let ignore = IgnorePatterns::new();
        let files = scan_files(dir.path(), &ignore).unwrap();

        assert_eq!(files.len(), 2);
    }

    #[test]
    fn test_scan_ignores_mic_dir() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join("file.txt"), "content").unwrap();
        fs::create_dir(dir.path().join(".hif")).unwrap();
        fs::write(dir.path().join(".hif/session.bin"), "session").unwrap();

        let ignore = IgnorePatterns::new();
        let files = scan_files(dir.path(), &ignore).unwrap();

        assert_eq!(files.len(), 1);
        assert!(files[0].ends_with("file.txt"));
    }
}
