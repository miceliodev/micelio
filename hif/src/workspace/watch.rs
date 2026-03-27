//! Workspace watcher state persisted under `.hif/watch/`.

use crate::error::Result;
use crate::workspace::HIF_DIR;
use serde::{Deserialize, Serialize};
use std::fs::{self, OpenOptions};
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

const WATCH_DIR: &str = "watch";
const CLIENTS_DIR: &str = "clients";
const WATCHER_STATE_FILE: &str = "watcher.json";
const SPAWN_LOCK_FILE: &str = "spawn.lock";
const FLUSH_REQUEST_FILE: &str = "flush.request";
const STOP_REQUEST_FILE: &str = "stop.request";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WatcherState {
    pub pid: u32,
    pub session_id: String,
    pub started_at: i64,
}

pub fn watch_dir(workspace_root: &Path) -> PathBuf {
    workspace_root.join(HIF_DIR).join(WATCH_DIR)
}

pub fn ensure_watch_dir(workspace_root: &Path) -> Result<PathBuf> {
    let dir = watch_dir(workspace_root);
    fs::create_dir_all(clients_dir(workspace_root))?;
    Ok(dir)
}

pub fn clients_dir(workspace_root: &Path) -> PathBuf {
    watch_dir(workspace_root).join(CLIENTS_DIR)
}

pub fn touch_client_heartbeat(workspace_root: &Path, shell_pid: u32) -> Result<()> {
    ensure_watch_dir(workspace_root)?;
    let path = client_path(workspace_root, shell_pid);
    fs::write(path, chrono::Utc::now().timestamp().to_string())?;
    Ok(())
}

pub fn remove_client_heartbeat(workspace_root: &Path, shell_pid: u32) -> Result<()> {
    let path = client_path(workspace_root, shell_pid);
    if path.exists() {
        fs::remove_file(path)?;
    }
    Ok(())
}

pub fn active_client_count(workspace_root: &Path, max_age: Duration) -> Result<usize> {
    let dir = clients_dir(workspace_root);
    if !dir.exists() {
        return Ok(0);
    }

    let now = SystemTime::now();
    let mut active = 0usize;

    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let metadata = entry.metadata()?;
        let is_fresh = metadata
            .modified()
            .ok()
            .and_then(|modified| now.duration_since(modified).ok())
            .map(|age| age <= max_age)
            .unwrap_or(false);

        if is_fresh {
            active += 1;
        } else if path.exists() {
            let _ = fs::remove_file(path);
        }
    }

    Ok(active)
}

pub fn save_watcher_state(workspace_root: &Path, state: &WatcherState) -> Result<()> {
    ensure_watch_dir(workspace_root)?;
    let path = watcher_state_path(workspace_root);
    let data = serde_json::to_vec(state)?;
    fs::write(path, data)?;
    Ok(())
}

pub fn load_watcher_state(workspace_root: &Path) -> Result<Option<WatcherState>> {
    let path = watcher_state_path(workspace_root);
    if !path.exists() {
        return Ok(None);
    }

    let data = fs::read(path)?;
    Ok(Some(serde_json::from_slice(&data)?))
}

pub fn clear_watcher_state(workspace_root: &Path) -> Result<()> {
    let path = watcher_state_path(workspace_root);
    if path.exists() {
        fs::remove_file(path)?;
    }
    Ok(())
}

pub fn watcher_process_is_alive(state: &WatcherState) -> bool {
    process_is_alive(state.pid)
}

pub fn try_acquire_spawn_lock(workspace_root: &Path, stale_after: Duration) -> Result<bool> {
    ensure_watch_dir(workspace_root)?;
    cleanup_dead_watcher(workspace_root)?;

    let lock_path = spawn_lock_path(workspace_root);
    if lock_path.exists() && is_stale(&lock_path, stale_after) {
        let _ = fs::remove_file(&lock_path);
    }

    match OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&lock_path)
    {
        Ok(mut file) => {
            writeln!(file, "{}", std::process::id())?;
            Ok(true)
        }
        Err(error) if error.kind() == ErrorKind::AlreadyExists => Ok(false),
        Err(error) => Err(error.into()),
    }
}

pub fn release_spawn_lock(workspace_root: &Path) -> Result<()> {
    let path = spawn_lock_path(workspace_root);
    if path.exists() {
        fs::remove_file(path)?;
    }
    Ok(())
}

pub fn request_flush(workspace_root: &Path) -> Result<()> {
    ensure_watch_dir(workspace_root)?;
    fs::write(flush_request_path(workspace_root), b"1")?;
    Ok(())
}

pub fn take_flush_request(workspace_root: &Path) -> Result<bool> {
    take_request(&flush_request_path(workspace_root))
}

pub fn request_stop(workspace_root: &Path) -> Result<()> {
    ensure_watch_dir(workspace_root)?;
    fs::write(stop_request_path(workspace_root), b"1")?;
    Ok(())
}

pub fn take_stop_request(workspace_root: &Path) -> Result<bool> {
    take_request(&stop_request_path(workspace_root))
}

pub fn clear_requests(workspace_root: &Path) -> Result<()> {
    for path in [
        flush_request_path(workspace_root),
        stop_request_path(workspace_root),
    ] {
        if path.exists() {
            fs::remove_file(path)?;
        }
    }
    Ok(())
}

fn cleanup_dead_watcher(workspace_root: &Path) -> Result<()> {
    let Some(state) = load_watcher_state(workspace_root)? else {
        return Ok(());
    };

    if !watcher_process_is_alive(&state) {
        clear_watcher_state(workspace_root)?;
    }

    Ok(())
}

fn watcher_state_path(workspace_root: &Path) -> PathBuf {
    watch_dir(workspace_root).join(WATCHER_STATE_FILE)
}

fn spawn_lock_path(workspace_root: &Path) -> PathBuf {
    watch_dir(workspace_root).join(SPAWN_LOCK_FILE)
}

fn flush_request_path(workspace_root: &Path) -> PathBuf {
    watch_dir(workspace_root).join(FLUSH_REQUEST_FILE)
}

fn stop_request_path(workspace_root: &Path) -> PathBuf {
    watch_dir(workspace_root).join(STOP_REQUEST_FILE)
}

fn client_path(workspace_root: &Path, shell_pid: u32) -> PathBuf {
    clients_dir(workspace_root).join(format!("{}.heartbeat", shell_pid))
}

fn take_request(path: &Path) -> Result<bool> {
    if path.exists() {
        fs::remove_file(path)?;
        Ok(true)
    } else {
        Ok(false)
    }
}

fn is_stale(path: &Path, stale_after: Duration) -> bool {
    fs::metadata(path)
        .ok()
        .and_then(|metadata| metadata.modified().ok())
        .and_then(|modified| SystemTime::now().duration_since(modified).ok())
        .map(|age| age >= stale_after)
        .unwrap_or(false)
}

fn process_is_alive(pid: u32) -> bool {
    #[cfg(unix)]
    {
        unsafe { libc::kill(pid as libc::pid_t, 0) == 0 }
    }

    #[cfg(not(unix))]
    {
        pid != 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn active_client_count_prunes_stale_heartbeats() {
        let dir = tempdir().unwrap();
        let workspace_root = dir.path();

        touch_client_heartbeat(workspace_root, 10).unwrap();
        assert_eq!(
            active_client_count(workspace_root, Duration::from_secs(60)).unwrap(),
            1
        );
        std::thread::sleep(Duration::from_millis(20));
        assert_eq!(
            active_client_count(workspace_root, Duration::from_secs(0)).unwrap(),
            0
        );
    }

    #[test]
    fn flush_request_is_consumed_once() {
        let dir = tempdir().unwrap();
        let workspace_root = dir.path();

        request_flush(workspace_root).unwrap();
        assert!(take_flush_request(workspace_root).unwrap());
        assert!(!take_flush_request(workspace_root).unwrap());
    }
}
