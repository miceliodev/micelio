//! Hidden commands for the automatic workspace watcher.

use crate::cli::{WatchCommand, WatchSubcommand};
use crate::commands::session;
use crate::error::{MicError, Result};
use crate::workspace::session::Session;
use crate::workspace::watch::{self, WatcherState};
use crate::workspace::{
    is_workspace_metadata_path, metadata_dir_for_root, workspace_root, WorkspaceManifest,
};
use notify::{RecursiveMode, Watcher};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::mpsc;
use std::time::{Duration, Instant};

const CLIENT_TTL: Duration = Duration::from_secs(15);
const IDLE_GRACE: Duration = Duration::from_secs(5);
const DEBOUNCE_WINDOW: Duration = Duration::from_secs(2);
const EVENT_POLL_INTERVAL: Duration = Duration::from_millis(500);
const SPAWN_LOCK_STALE_AFTER: Duration = Duration::from_secs(10);

pub async fn run(cmd: WatchCommand) -> Result<()> {
    match cmd.command {
        WatchSubcommand::Ensure {
            shell_pid,
            print_root,
            workspace_root,
        } => ensure(shell_pid, print_root, workspace_root),
        WatchSubcommand::Leave {
            workspace_root,
            shell_pid,
        } => leave(&workspace_root, shell_pid),
        WatchSubcommand::Run {
            workspace_root,
            session_id,
        } => tokio::task::spawn_blocking(move || run_loop(workspace_root, session_id))
            .await
            .map_err(|error| MicError::Other(format!("watcher task failed: {}", error)))?,
    }
}

fn ensure(shell_pid: u32, print_root: bool, explicit_root: Option<PathBuf>) -> Result<()> {
    let Some(workspace_root) = resolve_workspace_root(explicit_root)? else {
        return Ok(());
    };

    std::env::set_current_dir(&workspace_root)?;

    if WorkspaceManifest::load()?.is_none() {
        return Ok(());
    }

    let Some(state) = Session::load()? else {
        return Ok(());
    };

    watch::touch_client_heartbeat(&workspace_root, shell_pid)?;

    if let Some(watcher_state) = watch::load_watcher_state(&workspace_root)? {
        if watcher_state.session_id == state.id && watch::watcher_process_is_alive(&watcher_state) {
            maybe_print_root(print_root, &workspace_root);
            return Ok(());
        }

        let _ = watch::request_stop(&workspace_root);
    }

    if watch::try_acquire_spawn_lock(&workspace_root, SPAWN_LOCK_STALE_AFTER)? {
        if let Err(error) = spawn_watcher_process(&workspace_root, &state.id) {
            let _ = watch::release_spawn_lock(&workspace_root);
            return Err(error);
        }
    }

    maybe_print_root(print_root, &workspace_root);
    Ok(())
}

fn leave(workspace_root: &Path, shell_pid: u32) -> Result<()> {
    if !metadata_dir_for_root(workspace_root).exists() {
        return Ok(());
    }

    watch::remove_client_heartbeat(workspace_root, shell_pid)?;
    watch::request_flush(workspace_root)?;
    Ok(())
}

fn run_loop(workspace_root: PathBuf, session_id: String) -> Result<()> {
    std::env::set_current_dir(&workspace_root)?;
    watch::ensure_watch_dir(&workspace_root)?;
    watch::save_watcher_state(
        &workspace_root,
        &WatcherState {
            pid: std::process::id(),
            session_id: session_id.clone(),
            started_at: chrono::Utc::now().timestamp(),
        },
    )?;
    watch::release_spawn_lock(&workspace_root)?;
    let _guard = WatcherGuard::new(workspace_root.clone());

    let (tx, rx) = mpsc::channel();
    let mut watcher = notify::recommended_watcher(move |event| {
        let _ = tx.send(event);
    })
    .map_err(|error| MicError::Other(format!("failed to create watcher: {}", error)))?;

    watcher
        .watch(&workspace_root, RecursiveMode::Recursive)
        .map_err(|error| MicError::Other(format!("failed to watch workspace: {}", error)))?;

    let mut dirty = false;
    let mut last_event_at = None::<Instant>;
    let mut idle_since = None::<Instant>;

    loop {
        match Session::load()? {
            Some(state) if state.id == session_id => {}
            _ => break,
        }

        let stop_requested = watch::take_stop_request(&workspace_root)?;
        let flush_requested = watch::take_flush_request(&workspace_root)?;

        let active_clients = watch::active_client_count(&workspace_root, CLIENT_TTL)?;
        if active_clients == 0 {
            idle_since.get_or_insert_with(Instant::now);
        } else {
            idle_since = None;
        }

        if stop_requested {
            let _ = flush_dirty_changes(&mut dirty);
            break;
        }

        if flush_requested {
            let _ = flush_dirty_changes(&mut dirty);
        }

        if dirty
            && last_event_at
                .map(|last_event| last_event.elapsed() >= DEBOUNCE_WINDOW)
                .unwrap_or(false)
        {
            if sync_draft_once().is_ok() {
                dirty = false;
                last_event_at = None;
            }
        }

        if idle_since
            .map(|idle| idle.elapsed() >= IDLE_GRACE)
            .unwrap_or(false)
        {
            let _ = flush_dirty_changes(&mut dirty);
            break;
        }

        match rx.recv_timeout(EVENT_POLL_INTERVAL) {
            Ok(Ok(event)) => {
                if event
                    .paths
                    .iter()
                    .any(|path| is_relevant_path(&workspace_root, path))
                {
                    dirty = true;
                    last_event_at = Some(Instant::now());
                }
            }
            Ok(Err(_error)) => {}
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }

    Ok(())
}

fn flush_dirty_changes(dirty: &mut bool) -> Result<()> {
    if !*dirty {
        return Ok(());
    }

    if sync_draft_once().is_ok() {
        *dirty = false;
    }

    Ok(())
}

fn sync_draft_once() -> Result<()> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|error| MicError::Other(format!("failed to create runtime: {}", error)))?;
    runtime.block_on(session::sync_active_session_draft())
}

fn spawn_watcher_process(workspace_root: &Path, session_id: &str) -> Result<()> {
    let executable = std::env::current_exe()?;
    let mut command = std::process::Command::new(executable);
    command
        .arg("watch")
        .arg("run")
        .arg("--workspace-root")
        .arg(workspace_root)
        .arg("--session-id")
        .arg(session_id)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;

        unsafe {
            command.pre_exec(|| {
                libc::setsid();
                Ok(())
            });
        }
    }

    command.spawn()?;
    Ok(())
}

fn resolve_workspace_root(explicit_root: Option<PathBuf>) -> Result<Option<PathBuf>> {
    match explicit_root {
        Some(path) => Ok(Some(normalize_root(path))),
        None => Ok(workspace_root().ok()),
    }
}

fn normalize_root(path: PathBuf) -> PathBuf {
    path.canonicalize().unwrap_or(path)
}

fn maybe_print_root(print_root: bool, workspace_root: &Path) {
    if print_root {
        println!("{}", workspace_root.display());
    }
}

fn is_relevant_path(workspace_root: &Path, path: &Path) -> bool {
    let Ok(relative) = path.strip_prefix(workspace_root) else {
        return false;
    };

    if relative.as_os_str().is_empty() {
        return false;
    }

    let relative = relative.to_string_lossy();
    if is_workspace_metadata_path(&relative) || relative == ".git" || relative.starts_with(".git/")
    {
        return false;
    }

    !relative.split('/').any(|segment| segment == "node_modules")
}

struct WatcherGuard {
    workspace_root: PathBuf,
}

impl WatcherGuard {
    fn new(workspace_root: PathBuf) -> Self {
        Self { workspace_root }
    }
}

impl Drop for WatcherGuard {
    fn drop(&mut self) {
        let _ = watch::clear_requests(&self.workspace_root);
        let _ = watch::clear_watcher_state(&self.workspace_root);
        let _ = watch::release_spawn_lock(&self.workspace_root);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn relevant_paths_skip_internal_directories() {
        let root = PathBuf::from("/tmp/workspace");

        assert!(is_relevant_path(&root, &root.join("src/main.rs")));
        assert!(!is_relevant_path(
            &root,
            &root.join(".hif/watch/watcher.json")
        ));
        assert!(!is_relevant_path(&root, &root.join(".git/index")));
        assert!(!is_relevant_path(
            &root,
            &root.join("node_modules/pkg/index.js")
        ));
    }
}
