//! Workspace change detection.
//!
//! Detects changes between the workspace manifest and the actual files on disk.
#![allow(dead_code)]

use crate::error::Result;
use crate::workspace::{is_safe_path, is_workspace_metadata_path, WorkspaceManifest};
use ignore::DirEntry;
use ignore::WalkBuilder;
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

    let mut known_files: HashMap<String, String> = manifest
        .entries
        .iter()
        .map(|e| (e.path.clone(), e.hash.clone()))
        .collect();

    let files = scan_files(workspace_root)?;

    for file_path in &files {
        let relative = file_path
            .strip_prefix(workspace_root)
            .unwrap_or(file_path)
            .to_string_lossy()
            .replace(std::path::MAIN_SEPARATOR, "/");

        if !is_safe_path(&relative) || is_workspace_metadata_path(&relative) {
            continue;
        }

        if let Some(known_hash) = known_files.remove(&relative) {
            let content = fs::read(file_path)?;
            let current_hash = micelio_blob_hash_hex(&content);

            if current_hash != known_hash {
                changes.push(WorkspaceChange {
                    path: relative,
                    change_type: ChangeType::Modified,
                });
            }
        } else {
            changes.push(WorkspaceChange {
                path: relative,
                change_type: ChangeType::Added,
            });
        }
    }

    for path in known_files.keys() {
        changes.push(WorkspaceChange {
            path: path.clone(),
            change_type: ChangeType::Deleted,
        });
    }

    changes.sort_by(|a, b| a.path.cmp(&b.path));

    Ok(changes)
}

/// Scan files in the workspace using `.gitignore`-compatible `.hifignore` rules.
fn scan_files(root: &Path) -> Result<Vec<PathBuf>> {
    let mut builder = WalkBuilder::new(root);
    builder
        .hidden(false)
        .git_ignore(false)
        .git_global(false)
        .git_exclude(false)
        .ignore(false)
        .parents(true)
        .require_git(false)
        .add_custom_ignore_filename(".hifignore");
    builder.filter_entry(|entry| !is_default_ignored_entry(entry));

    let mut files = Vec::new();

    for entry in builder.build() {
        let entry = match entry {
            Ok(entry) => entry,
            Err(error) => {
                return Err(std::io::Error::other(error.to_string()).into());
            }
        };

        if entry.depth() == 0 || entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false) {
            continue;
        }

        files.push(entry.into_path());
    }

    Ok(files)
}

fn is_default_ignored_entry(entry: &DirEntry) -> bool {
    matches!(
        entry.file_name().to_str(),
        Some(".hif" | ".git" | "node_modules")
    ) || entry
        .path()
        .file_name()
        .and_then(|name| name.to_str())
        .map(|name| {
            name == ".DS_Store"
                || name.starts_with("._")
                || name.ends_with(".swp")
                || name.ends_with('~')
        })
        .unwrap_or(false)
}

fn micelio_blob_hash_hex(content: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content);
    format!("{:x}", hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_change_type_prefix() {
        assert_eq!(ChangeType::Added.prefix(), "A");
        assert_eq!(ChangeType::Modified.prefix(), "M");
        assert_eq!(ChangeType::Deleted.prefix(), "D");
    }

    #[test]
    fn test_scan_empty_dir() {
        let dir = tempdir().unwrap();
        let files = scan_files(dir.path()).unwrap();
        assert!(files.is_empty());
    }

    #[test]
    fn test_scan_with_files() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join("file.txt"), "content").unwrap();
        fs::create_dir(dir.path().join("subdir")).unwrap();
        fs::write(dir.path().join("subdir/nested.txt"), "nested").unwrap();

        let files = scan_files(dir.path()).unwrap();

        assert_eq!(
            relative_paths(dir.path(), &files),
            vec!["file.txt", "subdir/nested.txt"]
        );
    }

    #[test]
    fn test_scan_ignores_default_directories() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join("file.txt"), "content").unwrap();
        fs::create_dir(dir.path().join(".hif")).unwrap();
        fs::write(dir.path().join(".hif/session.bin"), "session").unwrap();
        fs::create_dir(dir.path().join("node_modules")).unwrap();
        fs::write(dir.path().join("node_modules/pkg.js"), "pkg").unwrap();

        let files = scan_files(dir.path()).unwrap();

        assert_eq!(relative_paths(dir.path(), &files), vec!["file.txt"]);
    }

    #[test]
    fn test_hifignore_supports_gitignore_globs() {
        let dir = tempdir().unwrap();
        fs::create_dir_all(dir.path().join("build/cache")).unwrap();
        fs::create_dir_all(dir.path().join("src")).unwrap();
        fs::write(dir.path().join("build/output.js"), "ignored").unwrap();
        fs::write(dir.path().join("build/cache/keep.txt"), "ignored").unwrap();
        fs::write(dir.path().join("src/main.rs"), "kept").unwrap();
        fs::write(dir.path().join("temp.log"), "ignored").unwrap();
        fs::write(dir.path().join(".hifignore"), "build/\n*.log\n").unwrap();

        let files = scan_files(dir.path()).unwrap();

        assert_eq!(
            relative_paths(dir.path(), &files),
            vec![".hifignore", "src/main.rs"]
        );
    }

    #[test]
    fn test_hifignore_supports_negation_inside_ignored_directory() {
        let dir = tempdir().unwrap();
        fs::create_dir_all(dir.path().join("dist/assets")).unwrap();
        fs::write(dir.path().join("dist/app.js"), "ignored").unwrap();
        fs::write(dir.path().join("dist/assets/keep.js"), "kept").unwrap();
        fs::write(
            dir.path().join(".hifignore"),
            "dist/**\n!dist/assets/\n!dist/assets/keep.js\n",
        )
        .unwrap();

        let files = scan_files(dir.path()).unwrap();

        assert_eq!(
            relative_paths(dir.path(), &files),
            vec![".hifignore", "dist/assets/keep.js"]
        );
    }

    #[test]
    fn test_nested_hifignore_files_are_applied() {
        let dir = tempdir().unwrap();
        fs::create_dir_all(dir.path().join("docs/drafts")).unwrap();
        fs::write(dir.path().join("docs/.hifignore"), "drafts/\n").unwrap();
        fs::write(dir.path().join("docs/guide.md"), "keep").unwrap();
        fs::write(dir.path().join("docs/drafts/wip.md"), "ignore").unwrap();

        let files = scan_files(dir.path()).unwrap();

        assert_eq!(
            relative_paths(dir.path(), &files),
            vec!["docs/.hifignore", "docs/guide.md"]
        );
    }

    fn relative_paths(root: &Path, files: &[PathBuf]) -> Vec<String> {
        let mut paths = files
            .iter()
            .map(|path| {
                path.strip_prefix(root)
                    .unwrap()
                    .to_string_lossy()
                    .replace(std::path::MAIN_SEPARATOR, "/")
            })
            .collect::<Vec<_>>();
        paths.sort();
        paths
    }
}
