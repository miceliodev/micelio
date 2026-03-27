//! Mount command - expose a lazy workspace through the local filesystem.

use crate::cli::{parse_repository_ref, MountCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::{Endpoint, GrpcClient};
use crate::mountfs;
use crate::output;
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

#[derive(Serialize)]
pub(crate) struct MountOutput {
    account: String,
    repository: String,
    path: PathBuf,
    available_files: usize,
    revision: String,
    mode: &'static str,
}

/// Run the mount command.
pub async fn run(cmd: MountCommand) -> Result<()> {
    ensure_supported_platform()?;

    let (account, repository) = parse_repository_ref(&cmd.repository).ok_or_else(|| {
        MicError::InvalidRepositoryRef(format!(
            "Invalid repository reference '{}'. Use format: account/repository",
            cmd.repository
        ))
    })?;

    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);
    let json_output = output::use_json();

    let mount_path = cmd.path.clone().unwrap_or_else(|| repository.to_string());
    let mount_path = PathBuf::from(&mount_path);
    prepare_mount_path(&mount_path)?;

    if !json_output {
        output::ui_line(format!(
            "Mounting {}/{} at {}",
            account,
            repository,
            mount_path.display()
        ));
    }

    let tree = mountfs::fetch_remote_tree(&client, account, repository).await?;
    let state_dir = mountfs::create_state_dir()?;
    let mut info = mountfs::persist_mount_state(
        &state_dir,
        &server,
        account,
        repository,
        &mount_path,
        cmd.port,
        &tree,
    )?;

    let cleanup_result = async {
        let child = mountfs::spawn_mount_server(&state_dir)?;
        info.server_pid = Some(child.id());
        mountfs::persist_mount_info(&state_dir, &info)?;
        let ready = mountfs::wait_for_ready(&state_dir, Duration::from_secs(10))?;
        info.server_pid = Some(ready.pid);
        mountfs::persist_mount_info(&state_dir, &info)?;

        let url = format!("http://127.0.0.1:{}/", ready.port);
        let activation = mountfs::mount_workspace(&url, &mount_path)?;
        info.mount_kind = activation.kind;
        info.mount_source = activation.mount_source;
        info.link_target = activation.link_target;
        mountfs::persist_mount_info(&state_dir, &info)?;
        Ok::<(), MicError>(())
    }
    .await;

    if let Err(error) = cleanup_result {
        let _ = mountfs::stop_mount_server(&info);
        let _ = fs::remove_dir_all(&state_dir);
        return Err(error);
    }

    let revision = encode_hex(&tree.revision_hash);
    if json_output {
        output::print_ok(
            "mount",
            MountOutput {
                account: account.to_string(),
                repository: repository.to_string(),
                path: mount_path,
                available_files: tree.entries.len(),
                revision,
                mode: "lazy",
            },
        )?;
    } else {
        output::set_success_message(format!(
            "Mounted lazy workspace '{}/{}' at '{}'.",
            account,
            repository,
            mount_path.display()
        ));
        output::add_next_step(format!("cd {}", mount_path.display()));
        output::add_next_step(format!("hif unmount {}", mount_path.display()));
    }

    Ok(())
}

fn ensure_supported_platform() -> Result<()> {
    if cfg!(target_os = "macos") || cfg!(target_os = "linux") || cfg!(windows) {
        return Ok(());
    }

    Err(MicError::Other(
        "Lazy mount currently supports macOS, Linux, and Windows.".to_string(),
    ))
}

fn prepare_mount_path(path: &Path) -> Result<()> {
    if path.exists() {
        if !path.is_dir() {
            return Err(MicError::Other(format!(
                "Mount path must be a directory: {}",
                path.display()
            )));
        }

        if fs::read_dir(path)?.next().is_some() {
            return Err(MicError::Other(format!(
                "Mount path must be empty before mounting: {}",
                path.display()
            )));
        }

        return Ok(());
    }

    fs::create_dir_all(path)?;
    Ok(())
}

fn encode_hex(bytes: &[u8]) -> String {
    bytes
        .iter()
        .map(|byte| format!("{:02x}", byte))
        .collect::<String>()
}

#[cfg(test)]
mod tests {
    use super::prepare_mount_path;
    use tempfile::tempdir;

    #[test]
    fn prepare_mount_path_rejects_non_empty_directory() {
        let dir = tempdir().unwrap();
        std::fs::write(dir.path().join("README.md"), "hello").unwrap();

        let error = prepare_mount_path(dir.path()).unwrap_err();
        assert!(error
            .to_string()
            .contains("Mount path must be empty before mounting"));
    }
}
