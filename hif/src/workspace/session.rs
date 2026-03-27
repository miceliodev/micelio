//! Session management for hif.
//!
//! A session represents a unit of work with a goal, conversation,
//! decisions, and file changes.
#![allow(dead_code)]

use crate::core::Bloom;
use crate::error::{MicError, Result};
use crate::workspace::{
    clear_overlay, ensure_hif_dir, ensure_overlay_dir, hif_dir, is_safe_path,
    is_workspace_metadata_path, workspace_root, OVERLAY_DIR, SESSION_FILE,
};
use base64::Engine;
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, SystemTime};

const SESSION_LOCK_FILE: &str = "session.lock";
const SESSION_LOCK_STALE_AFTER: Duration = Duration::from_secs(30);
const SESSION_LOCK_RETRY: Duration = Duration::from_millis(10);
const SESSION_LOCK_TIMEOUT: Duration = Duration::from_secs(2);

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
    /// Last successfully synced draft epoch.
    #[serde(default)]
    pub sync_epoch: u32,
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
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
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
        Self::with_session_lock(|| Self::save_unlocked(state))
    }

    /// Delete the current session.
    pub fn delete() -> Result<()> {
        Self::with_session_lock(|| {
            let path = Self::session_path()?;
            if path.exists() {
                fs::remove_file(&path)?;
            }
            clear_overlay()?;
            Ok(())
        })
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
        Self::with_session_lock(|| {
            if Self::session_path()?.exists() {
                return Err(MicError::SessionAlreadyActive);
            }

            let now = chrono::Utc::now().timestamp().to_string();

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
                sync_epoch: 0,
                bloom_data: Some(bloom_data),
                bloom_hashes: bloom.num_hashes(),
            };

            clear_overlay()?;
            ensure_overlay_dir()?;
            Self::save_unlocked(&state)?;
            Ok(state)
        })
    }

    /// Add a note to the current session.
    pub fn add_note(role: &str, message: &str) -> Result<()> {
        Self::update_state(|state| {
            let now = chrono::Utc::now().timestamp().to_string();
            state.conversation.push(Conversation {
                role: role.to_string(),
                message: message.to_string(),
                timestamp: now,
            });
            Ok(())
        })
    }

    /// Add a decision to the current session.
    pub fn add_decision(description: &str, reasoning: &str) -> Result<()> {
        Self::update_state(|state| {
            let now = chrono::Utc::now().timestamp().to_string();
            state.decisions.push(Decision {
                description: description.to_string(),
                reasoning: reasoning.to_string(),
                timestamp: now,
            });
            Ok(())
        })
    }

    /// Write a file and stage the change.
    pub fn write_file(path: &str, content: &[u8]) -> Result<()> {
        if !is_safe_path(path) || is_workspace_metadata_path(path) {
            return Err(MicError::InvalidPath(path.to_string()));
        }

        let workspace_path = workspace_file_path(path)?;
        ensure_parent_dir(&workspace_path)?;
        fs::write(&workspace_path, content)?;
        Self::stage_file_change(path, Some(content), "modified")
    }

    /// Stage a file change from the current workspace.
    pub fn stage_file_change(path: &str, content: Option<&[u8]>, change_type: &str) -> Result<()> {
        if !is_safe_path(path) || is_workspace_metadata_path(path) {
            return Err(MicError::InvalidPath(path.to_string()));
        }

        Self::update_state(|state| {
            let content_str = match content {
                Some(bytes) => {
                    let overlay_path = overlay_file_path(path)?;
                    ensure_parent_dir(&overlay_path)?;
                    fs::write(&overlay_path, bytes)?;
                    String::from_utf8_lossy(bytes).to_string()
                }
                None => {
                    remove_overlay_file(path)?;
                    String::new()
                }
            };

            let change = FileChange {
                path: path.to_string(),
                content: content_str,
                change_type: change_type.to_string(),
            };

            if let Some(existing) = state.files.iter_mut().find(|file| file.path == path) {
                *existing = change;
            } else {
                state.files.push(change);
            }

            update_bloom(state, path);
            Ok(())
        })
    }

    /// Replace the session file list with the current workspace snapshot.
    pub fn replace_file_changes(files: Vec<FileChange>) -> Result<()> {
        for file in &files {
            if !is_safe_path(&file.path) || is_workspace_metadata_path(&file.path) {
                return Err(MicError::InvalidPath(file.path.clone()));
            }
        }

        Self::update_state(move |state| {
            let previous_paths = state
                .files
                .iter()
                .map(|file| file.path.clone())
                .collect::<std::collections::HashSet<_>>();
            let next_paths = files
                .iter()
                .map(|file| file.path.clone())
                .collect::<std::collections::HashSet<_>>();

            for removed_path in previous_paths.difference(&next_paths) {
                remove_overlay_file(removed_path)?;
            }

            for file in &files {
                sync_overlay_file(file)?;
            }

            state.files = files;
            rebuild_bloom(state);
            Ok(())
        })
    }

    /// Persist the latest synced draft epoch.
    pub fn set_sync_epoch(epoch: u32) -> Result<()> {
        Self::update_state(|state| {
            state.sync_epoch = epoch;
            Ok(())
        })
    }

    /// Get files from the overlay for landing or draft sync.
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

    /// Serialize session state to disk.
    fn serialize(state: &SessionState) -> Result<Vec<u8>> {
        Ok(serde_json::to_vec(state)?)
    }

    /// Deserialize session state from disk.
    fn deserialize(data: &[u8]) -> Result<SessionState> {
        Ok(serde_json::from_slice(data)?)
    }

    fn update_state<F>(mutate: F) -> Result<()>
    where
        F: FnOnce(&mut SessionState) -> Result<()>,
    {
        Self::with_session_lock(|| {
            let path = Self::session_path()?;
            if !path.exists() {
                return Err(MicError::NoActiveSession);
            }

            let data = fs::read(&path)?;
            let mut state = Self::deserialize(&data)?;
            mutate(&mut state)?;
            Self::save_unlocked(&state)
        })
    }

    fn save_unlocked(state: &SessionState) -> Result<()> {
        ensure_hif_dir()?;
        let path = Self::session_path()?;
        let data = Self::serialize(state)?;
        let temp_path = path.with_extension(format!("tmp.{}", std::process::id()));
        fs::write(&temp_path, data)?;

        #[cfg(windows)]
        if path.exists() {
            fs::remove_file(&path)?;
        }

        fs::rename(&temp_path, &path)?;
        Ok(())
    }

    fn with_session_lock<T, F>(operation: F) -> Result<T>
    where
        F: FnOnce() -> Result<T>,
    {
        let _guard = SessionLockGuard::acquire()?;
        operation()
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

fn workspace_file_path(path: &str) -> Result<PathBuf> {
    Ok(workspace_root()?.join(path))
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

fn sync_overlay_file(file: &FileChange) -> Result<()> {
    match file.change_type.as_str() {
        "deleted" => remove_overlay_file(&file.path),
        _ => {
            let overlay_path = overlay_file_path(&file.path)?;
            ensure_parent_dir(&overlay_path)?;
            fs::write(overlay_path, file.content.as_bytes())?;
            Ok(())
        }
    }
}

fn remove_overlay_file(path: &str) -> Result<()> {
    let overlay_path = overlay_file_path(path)?;

    if overlay_path.exists() {
        fs::remove_file(overlay_path)?;
    }

    Ok(())
}

fn update_bloom(state: &mut SessionState, path: &str) {
    if let Some(ref bloom_data) = state.bloom_data {
        if let Ok(bloom_bytes) = base64::engine::general_purpose::STANDARD.decode(bloom_data) {
            if let Some(mut bloom) = Bloom::deserialize(&bloom_bytes) {
                bloom.add(path);
                state.bloom_data =
                    Some(base64::engine::general_purpose::STANDARD.encode(bloom.serialize()));
            }
        }
    }
}

fn rebuild_bloom(state: &mut SessionState) {
    let bloom = Bloom::new(1000, 0.01).unwrap();

    let bloom = state.files.iter().fold(bloom, |mut bloom, change| {
        bloom.add(&change.path);
        bloom
    });

    state.bloom_data = Some(base64::engine::general_purpose::STANDARD.encode(bloom.serialize()));
    state.bloom_hashes = bloom.num_hashes();
}

/// Ensure the parent directory exists for a path.
fn ensure_parent_dir(path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() && !parent.exists() {
            fs::create_dir_all(parent)?;
        }
    }
    Ok(())
}

struct SessionLockGuard {
    path: PathBuf,
}

impl SessionLockGuard {
    fn acquire() -> Result<Self> {
        ensure_hif_dir()?;
        let path = hif_dir()?.join(SESSION_LOCK_FILE);
        let start = SystemTime::now();

        loop {
            if try_create_lock(&path)? {
                return Ok(Self { path });
            }

            if is_stale_lock(&path, SESSION_LOCK_STALE_AFTER) {
                let _ = fs::remove_file(&path);
                continue;
            }

            let waited = SystemTime::now().duration_since(start).unwrap_or_default();
            if waited >= SESSION_LOCK_TIMEOUT {
                return Err(MicError::Other(
                    "Timed out waiting for session state lock".to_string(),
                ));
            }

            thread::sleep(SESSION_LOCK_RETRY);
        }
    }
}

impl Drop for SessionLockGuard {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn try_create_lock(path: &Path) -> Result<bool> {
    match fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(path)
    {
        Ok(mut file) => {
            use std::io::Write;
            writeln!(file, "{}", std::process::id())?;
            Ok(true)
        }
        Err(error) if error.kind() == ErrorKind::AlreadyExists => Ok(false),
        Err(error) => Err(error.into()),
    }
}

fn is_stale_lock(path: &Path, stale_after: Duration) -> bool {
    fs::metadata(path)
        .ok()
        .and_then(|metadata| metadata.modified().ok())
        .and_then(|modified| SystemTime::now().duration_since(modified).ok())
        .map(|age| age >= stale_after)
        .unwrap_or(false)
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
            sync_epoch: 0,
            bloom_data: None,
            bloom_hashes: 7,
        };

        let data = Session::serialize(&state).unwrap();
        let loaded = Session::deserialize(&data).unwrap();

        assert_eq!(loaded.id, state.id);
        assert_eq!(loaded.goal, state.goal);
        assert_eq!(loaded.repository_org, state.repository_org);
        assert_eq!(loaded.conversation.len(), 1);
        assert_eq!(loaded.sync_epoch, 0);
    }

    #[test]
    fn session_state_defaults_missing_sync_epoch() {
        let data = br#"{
            "id": "test-id",
            "goal": "Test goal",
            "repository_org": "acme",
            "repository_handle": "app",
            "started_at": "1234567890",
            "conversation": [],
            "decisions": [],
            "files": [],
            "bloom_data": null,
            "bloom_hashes": 7
        }"#;

        let loaded = Session::deserialize(data).unwrap();
        assert_eq!(loaded.sync_epoch, 0);
    }
}
