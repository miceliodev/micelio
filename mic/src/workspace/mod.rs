//! Workspace management for mic.
//!
//! A workspace is a local directory linked to a Micelio project.
//! It contains a `.mic` directory with metadata and overlay files.

pub mod changes;
pub mod manifest;
pub mod session;

pub use changes::{ChangeType, collect_changes};

#[allow(unused_imports)]
pub use manifest::{Manifest, WorkspaceManifest, WorkspaceEntry};

// Re-exports for library API
#[allow(unused_imports)]
pub use session::{Session, SessionState};

use crate::error::Result;
use std::path::PathBuf;

/// The mic directory name.
pub const MIC_DIR: &str = ".mic";

/// The session file name.
pub const SESSION_FILE: &str = "session.bin";

/// The manifest file name.
pub const MANIFEST_FILE: &str = "manifest.json";

/// The overlay directory name.
pub const OVERLAY_DIR: &str = "overlay";

/// Get the .mic directory for the current working directory.
pub fn mic_dir() -> Result<PathBuf> {
    let cwd = std::env::current_dir()?;
    Ok(cwd.join(MIC_DIR))
}

/// Ensure the .mic directory exists.
pub fn ensure_mic_dir() -> Result<PathBuf> {
    let dir = mic_dir()?;
    if !dir.exists() {
        std::fs::create_dir_all(&dir)?;
    }
    Ok(dir)
}

/// Ensure the overlay directory exists.
pub fn ensure_overlay_dir() -> Result<PathBuf> {
    let dir = mic_dir()?.join(OVERLAY_DIR);
    if !dir.exists() {
        std::fs::create_dir_all(&dir)?;
    }
    Ok(dir)
}

/// Clear the overlay directory.
pub fn clear_overlay() -> Result<()> {
    let dir = mic_dir()?.join(OVERLAY_DIR);
    if dir.exists() {
        std::fs::remove_dir_all(&dir)?;
    }
    Ok(())
}

/// Check if a path is safe (no path traversal).
pub fn is_safe_path(path: &str) -> bool {
    if path.is_empty() {
        return false;
    }

    // Reject absolute paths
    if path.starts_with('/') || path.starts_with('\\') {
        return false;
    }

    // Check for path traversal
    for segment in path.split(&['/', '\\'][..]) {
        if segment == ".." {
            return false;
        }
    }

    true
}

/// Parse a project reference (account/project).
#[allow(dead_code)]
pub fn parse_project_ref(value: &str) -> Option<(String, String)> {
    let slash_index = value.find('/')?;
    
    if slash_index == 0 || slash_index + 1 >= value.len() {
        return None;
    }
    
    // Check for multiple slashes
    if value[slash_index + 1..].contains('/') {
        return None;
    }

    let account = &value[..slash_index];
    let project = &value[slash_index + 1..];

    Some((account.to_string(), project.to_string()))
}

/// Parse a position string like "@10", "10", "@latest", or "HEAD".
#[derive(Debug, Clone, PartialEq)]
pub enum PositionOrLatest {
    Position(u64),
    Latest,
}

pub fn parse_position(value: &str) -> Option<PositionOrLatest> {
    // Handle @position:N format
    if let Some(rest) = value.strip_prefix("@position:") {
        let pos = rest.parse().ok()?;
        return Some(PositionOrLatest::Position(pos));
    }

    // Handle @N or N format
    let trimmed = value.strip_prefix('@').unwrap_or(value);
    
    if trimmed.is_empty() {
        return None;
    }

    // Check for latest/head
    let lower = trimmed.to_lowercase();
    if lower == "latest" || lower == "head" {
        return Some(PositionOrLatest::Latest);
    }

    // Try to parse as number
    let pos = trimmed.parse().ok()?;
    Some(PositionOrLatest::Position(pos))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_safe_path() {
        assert!(is_safe_path("src/main.rs"));
        assert!(is_safe_path("README.md"));
        assert!(is_safe_path("path/to/file.txt"));
        
        assert!(!is_safe_path(""));
        assert!(!is_safe_path("/etc/passwd"));
        assert!(!is_safe_path("../secret"));
        assert!(!is_safe_path("path/../secret"));
    }

    #[test]
    fn test_parse_project_ref() {
        assert_eq!(
            parse_project_ref("acme/app"),
            Some(("acme".to_string(), "app".to_string()))
        );
        assert_eq!(
            parse_project_ref("org/project-name"),
            Some(("org".to_string(), "project-name".to_string()))
        );
        
        assert_eq!(parse_project_ref("noSlash"), None);
        assert_eq!(parse_project_ref("/project"), None);
        assert_eq!(parse_project_ref("account/"), None);
        assert_eq!(parse_project_ref("a/b/c"), None);
    }

    #[test]
    fn test_parse_position() {
        assert_eq!(parse_position("@10"), Some(PositionOrLatest::Position(10)));
        assert_eq!(parse_position("10"), Some(PositionOrLatest::Position(10)));
        assert_eq!(parse_position("@position:42"), Some(PositionOrLatest::Position(42)));
        assert_eq!(parse_position("@latest"), Some(PositionOrLatest::Latest));
        assert_eq!(parse_position("latest"), Some(PositionOrLatest::Latest));
        assert_eq!(parse_position("HEAD"), Some(PositionOrLatest::Latest));
        assert_eq!(parse_position("@head"), Some(PositionOrLatest::Latest));
        
        assert_eq!(parse_position(""), None);
        assert_eq!(parse_position("@"), None);
        assert_eq!(parse_position("invalid"), None);
    }
}
