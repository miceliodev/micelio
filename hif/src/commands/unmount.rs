//! Unmount command - detach a lazy workspace or remove a legacy mirror.

use crate::cli::UnmountCommand;
use crate::error::{MicError, Result};
use crate::mountfs::{self, LazyMountInfo};
use crate::output;
use crate::workspace::{WorkspaceManifest, HIF_DIR};
use serde::Serialize;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Serialize)]
pub(crate) struct UnmountOutput {
    path: PathBuf,
    removed: bool,
}

/// Run the unmount command.
pub async fn run(cmd: UnmountCommand) -> Result<()> {
    let json_output = output::use_json();
    let mount_path = PathBuf::from(&cmd.path);

    if !mount_path.exists() {
        return Err(MicError::Other(format!(
            "Mount path does not exist: {}",
            cmd.path
        )));
    }

    let hif_dir = mount_path.join(HIF_DIR);
    if !hif_dir.exists() {
        return Err(MicError::Other(format!(
            "Not a hif workspace: {}",
            cmd.path
        )));
    }

    let manifest_path = hif_dir.join("manifest.json");
    let manifest =
        WorkspaceManifest::load_from(&manifest_path)?.ok_or_else(|| MicError::NoWorkspace)?;

    if !json_output {
        output::ui_line(format!(
            "Unmounting {}/{} from {}",
            manifest.account,
            manifest.repository,
            mount_path.display()
        ));
    }

    if !confirm_if_active_session(&mount_path, json_output)? {
        return Ok(());
    }

    if let Some(info) = mountfs::workspace_mount_info(&mount_path)? {
        return run_lazy_unmount(cmd, &mount_path, info, json_output).await;
    }

    run_legacy_unmount(cmd, mount_path, json_output)
}

async fn run_lazy_unmount(
    cmd: UnmountCommand,
    mount_path: &Path,
    info: LazyMountInfo,
    json_output: bool,
) -> Result<()> {
    mountfs::unmount_workspace(&info, mount_path)?;
    mountfs::stop_mount_server(&info)?;

    if cmd.remove {
        if mount_path.exists() {
            fs::remove_dir_all(mount_path)?;
        }
        cleanup_mount_state(&info)?;
        return finish_unmount(mount_path.to_path_buf(), true, json_output);
    }

    mountfs::materialize_mount(&info, mount_path).await?;
    let mount_info_path = mount_path.join(HIF_DIR).join("mount.json");
    if mount_info_path.exists() {
        fs::remove_file(&mount_info_path)?;
    }
    cleanup_mount_state(&info)?;
    finish_unmount(mount_path.to_path_buf(), false, json_output)
}

fn run_legacy_unmount(cmd: UnmountCommand, mount_path: PathBuf, json_output: bool) -> Result<()> {
    let hif_dir = mount_path.join(HIF_DIR);
    fs::remove_dir_all(&hif_dir)?;

    if cmd.remove {
        for entry in fs::read_dir(&mount_path)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                fs::remove_dir_all(&path)?;
            } else {
                fs::remove_file(&path)?;
            }
        }

        fs::remove_dir(&mount_path)?;
        return finish_unmount(mount_path, true, json_output);
    }

    finish_unmount(mount_path, false, json_output)
}

fn finish_unmount(path: PathBuf, removed: bool, json_output: bool) -> Result<()> {
    if json_output {
        output::print_ok("unmount", UnmountOutput { path, removed })?;
        return Ok(());
    }

    if removed {
        output::set_success_message(format!("Removed '{}'.", path.display()));
    } else {
        output::set_success_message(format!("Unmounted; files remain at '{}'.", path.display()));
        output::add_next_step(format!("hif unmount {} --remove", path.display()));
    }

    Ok(())
}

fn confirm_if_active_session(mount_path: &Path, json_output: bool) -> Result<bool> {
    let session_path = mount_path.join(HIF_DIR).join("session.bin");
    if !session_path.exists() {
        return Ok(true);
    }

    if json_output {
        return Err(MicError::Other(
            "Active session with uncommitted changes. Run 'hif session land' or 'hif session abandon' first.".to_string(),
        ));
    }

    output::warn("Active session with uncommitted changes.");
    output::add_next_step("hif session land");
    output::add_next_step("hif session abandon");
    output::ui_text("Continue anyway? [y/N] ");
    std::io::stdout().flush()?;

    let mut input = String::new();
    std::io::stdin().read_line(&mut input)?;
    if input.trim().eq_ignore_ascii_case("y") {
        return Ok(true);
    }

    output::set_success_message("Unmount aborted.");
    Ok(false)
}

fn cleanup_mount_state(info: &LazyMountInfo) -> Result<()> {
    let state_dir = PathBuf::from(&info.state_dir);
    if state_dir.exists() {
        fs::remove_dir_all(state_dir)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use crate::commands::ui_test_support::assert_output_snapshot_with_setup;

    #[test]
    fn ui_snapshot_unmount_missing_path() {
        assert_output_snapshot_with_setup(
            &["unmount", "/tmp/hif-ui-snapshot-missing-path"],
            1,
            "",
            "error: Mount path does not exist: /tmp/hif-ui-snapshot-missing-path\n",
            |_home, _cwd| {
                let _ = std::fs::remove_file("/tmp/hif-ui-snapshot-missing-path");
                let _ = std::fs::remove_dir_all("/tmp/hif-ui-snapshot-missing-path");
            },
        );
    }
}
