//! Session management for hif.
//!
//! A session represents a unit of work with a goal, conversation,
//! decisions, and file changes.
#![allow(dead_code)]

use crate::core::Bloom;
use crate::error::{MicError, Result};
use crate::workspace::{
    clear_overlay, ensure_hif_dir, ensure_overlay_dir, hif_dir, is_safe_path, OVERLAY_DIR,
    SESSION_FILE,
};
use base64::Engine;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

/// Session state stored on disk.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionState {
    /// Session ID.
    pub id: String,
    /// Session goal.
    pub goal: String,
    /// Repository organization.
    pub repository_org: String,
    /// Repository handle.
    pub repository_handle: String,
    /// Session start timestamp.
    pub started_at: String,
    /// Conversation messages.
    #[serde(default)]
    pub conversation: Vec<Conversation>,
    /// Decisions made during the session.
    #[serde(default)]
    pub decisions: Vec<Decision>,
    /// File changes.
    #[serde(default)]
    pub files: Vec<FileChange>,
    /// Base64-encoded bloom filter for path tracking.
    pub bloom_data: Option<String>,
    /// Number of hash functions used in bloom filter.
    #[serde(default = "default_bloom_hashes")]
    pub bloom_hashes: u32,
}

fn default_bloom_hashes() -> u32 {
    7
}

/// A conversation message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    /// Role (human or agent).
    pub role: String,
    /// Message content.
    pub message: String,
    /// Timestamp.
    pub timestamp: String,
}

/// A decision made during the session.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Decision {
    /// Description of the decision.
    pub description: String,
    /// Reasoning behind the decision.
    pub reasoning: String,
    /// Timestamp.
    pub timestamp: String,
}

/// A file change in the session.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileChange {
    /// File path.
    pub path: String,
    /// File content.
    pub content: String,
    /// Change type (added, modified, deleted).
    pub change_type: String,
}

/// Session manager.
pub struct Session;

impl Session {
    /// Get the session file path.
    pub fn session_path() -> Result<PathBuf> {
        Ok(hif_dir()?.join(SESSION_FILE))
    }

    /// Check if there's an active session.
    pub fn exists() -> Result<bool> {
        let path = Self::session_path()?;
        Ok(path.exists())
    }

    /// Load the current session state.
    pub fn load() -> Result<Option<SessionState>> {
        let path = Self::session_path()?;

        if !path.exists() {
            return Ok(None);
        }

        let data = fs::read(&path)?;
        let state = Self::deserialize(&data)?;
        Ok(Some(state))
    }

    /// Save the session state.
    pub fn save(state: &SessionState) -> Result<()> {
        ensure_hif_dir()?;
        let path = Self::session_path()?;
        let data = Self::serialize(state)?;
        fs::write(&path, data)?;
        Ok(())
    }

    /// Delete the current session.
    pub fn delete() -> Result<()> {
        let path = Self::session_path()?;
        if path.exists() {
            fs::remove_file(&path)?;
        }
        clear_overlay()?;
        Ok(())
    }

    /// Start a new session.
    pub fn start(org: &str, repository: &str, goal: &str) -> Result<SessionState> {
        let session_id = generate_session_id();
        Self::start_with_id(org, repository, goal, &session_id)
    }

    /// Start a new session with an explicit session id.
    pub fn start_with_id(
        org: &str,
        repository: &str,
        goal: &str,
        session_id: &str,
    ) -> Result<SessionState> {
        if Self::exists()? {
            return Err(MicError::SessionAlreadyActive);
        }

        let now = chrono::Utc::now().timestamp().to_string();

        // Create bloom filter for path tracking
        let bloom = Bloom::new(1000, 0.01).unwrap();
        let bloom_data = base64::engine::general_purpose::STANDARD.encode(bloom.serialize());

        let state = SessionState {
            id: session_id.to_string(),
            goal: goal.to_string(),
            repository_org: org.to_string(),
            repository_handle: repository.to_string(),
            started_at: now,
            conversation: Vec::new(),
            decisions: Vec::new(),
            files: Vec::new(),
            bloom_data: Some(bloom_data),
            bloom_hashes: bloom.num_hashes(),
        };

        // Clear and create overlay directory
        clear_overlay()?;
        ensure_overlay_dir()?;

        Self::save(&state)?;
        Ok(state)
    }

    /// Add a note to the current session.
    pub fn add_note(role: &str, message: &str) -> Result<()> {
        let mut state = Self::load()?.ok_or(MicError::NoActiveSession)?;

        let now = chrono::Utc::now().timestamp().to_string();
        state.conversation.push(Conversation {
            role: role.to_string(),
            message: message.to_string(),
            timestamp: now,
        });

        Self::save(&state)?;
        Ok(())
    }

    /// Write a file and stage the change.
    pub fn write_file(path: &str, content: &[u8]) -> Result<()> {
        if !is_safe_path(path) {
            return Err(MicError::InvalidPath(path.to_string()));
        }

        let mut state = Self::load()?.ok_or(MicError::NoActiveSession)?;

        // Write to actual file
        ensure_parent_dir(path)?;
        fs::write(path, content)?;

        // Write to overlay
        let overlay_path = overlay_file_path(path)?;
        ensure_parent_dir(&overlay_path.to_string_lossy())?;
        fs::write(&overlay_path, content)?;

        // Update file changes
        let content_str = String::from_utf8_lossy(content).to_string();
        let change = FileChange {
            path: path.to_string(),
            content: content_str,
            change_type: "modified".to_string(),
        };

        // Upsert the change
        if let Some(existing) = state.files.iter_mut().find(|f| f.path == path) {
            *existing = change;
        } else {
            state.files.push(change);
        }

        // Update bloom filter
        if let Some(ref bloom_data) = state.bloom_data {
            if let Ok(bloom_bytes) = base64::engine::general_purpose::STANDARD.decode(bloom_data) {
                if let Some(mut bloom) = Bloom::deserialize(&bloom_bytes) {
                    bloom.add(path);
                    state.bloom_data =
                        Some(base64::engine::general_purpose::STANDARD.encode(bloom.serialize()));
                }
            }
        }

        Self::save(&state)?;
        Ok(())
    }

    /// Get files from the overlay for landing.
    pub fn get_overlay_files() -> Result<Vec<FileChange>> {
        let state = Self::load()?.ok_or(MicError::NoActiveSession)?;

        let mut files = Vec::new();
        for file in &state.files {
            let content = if file.change_type == "deleted" {
                String::new()
            } else if let Some(overlay_content) = read_overlay_file(&file.path)? {
                overlay_content
            } else {
                file.content.clone()
            };

            files.push(FileChange {
                path: file.path.clone(),
                content,
                change_type: file.change_type.clone(),
            });
        }

        Ok(files)
    }

    /// Load the bloom filter from the current session.
    pub fn load_bloom() -> Result<Option<Bloom>> {
        let state = Self::load()?;

        if let Some(state) = state {
            if let Some(ref bloom_data) = state.bloom_data {
                if let Ok(bloom_bytes) =
                    base64::engine::general_purpose::STANDARD.decode(bloom_data)
                {
                    return Ok(Bloom::deserialize(&bloom_bytes));
                }
            }
        }

        Ok(None)
    }

    /// Serialize session state to binary.
    fn serialize(state: &SessionState) -> Result<Vec<u8>> {
        // Using JSON for simplicity - could use binary format for efficiency
        let json = serde_json::to_vec(state)?;
        Ok(json)
    }

    /// Deserialize session state from binary.
    fn deserialize(data: &[u8]) -> Result<SessionState> {
        let state: SessionState = serde_json::from_slice(data)?;
        Ok(state)
    }
}

/// Generate a random session ID.
fn generate_session_id() -> String {
    let bytes: [u8; 16] = rand::random();
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

/// Get the overlay file path for a given path.
fn overlay_file_path(path: &str) -> Result<PathBuf> {
    Ok(hif_dir()?.join(OVERLAY_DIR).join(path))
}

/// Read a file from the overlay.
fn read_overlay_file(path: &str) -> Result<Option<String>> {
    let overlay_path = overlay_file_path(path)?;

    if !overlay_path.exists() {
        return Ok(None);
    }

    let content = fs::read_to_string(&overlay_path)?;
    Ok(Some(content))
}

/// Ensure the parent directory exists for a path.
fn ensure_parent_dir(path: &str) -> Result<()> {
    if let Some(parent) = std::path::Path::new(path).parent() {
        if !parent.as_os_str().is_empty() && !parent.exists() {
            fs::create_dir_all(parent)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_session_id_is_unique() {
        let id1 = generate_session_id();
        let id2 = generate_session_id();
        assert_ne!(id1, id2);
        assert!(!id1.is_empty());
    }

    #[test]
    fn session_state_serialization() {
        let state = SessionState {
            id: "test-id".to_string(),
            goal: "Test goal".to_string(),
            repository_org: "acme".to_string(),
            repository_handle: "app".to_string(),
            started_at: "1234567890".to_string(),
            conversation: vec![Conversation {
                role: "human".to_string(),
                message: "Hello".to_string(),
                timestamp: "1234567890".to_string(),
            }],
            decisions: Vec::new(),
            files: Vec::new(),
            bloom_data: None,
            bloom_hashes: 7,
        };

        let data = Session::serialize(&state).unwrap();
        let loaded = Session::deserialize(&data).unwrap();

        assert_eq!(loaded.id, state.id);
        assert_eq!(loaded.goal, state.goal);
        assert_eq!(loaded.repository_org, state.repository_org);
        assert_eq!(loaded.conversation.len(), 1);
    }
}
