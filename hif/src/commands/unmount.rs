//! Unmount command - unmount repository virtual filesystem.

use crate::cli::UnmountCommand;
use crate::error::{MicError, Result};
use crate::output;
use crate::workspace::{WorkspaceManifest, HIF_DIR};
use serde::Serialize;
use std::fs;
use std::path::PathBuf;

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

    // Check if this is a hif workspace
    let hif_dir = mount_path.join(HIF_DIR);
    if !hif_dir.exists() {
        return Err(MicError::Other(format!(
            "Not a hif workspace: {}",
            cmd.path
        )));
    }

    // Load manifest to get repository info
    let manifest_path = hif_dir.join("manifest.json");
    let manifest =
        WorkspaceManifest::load_from(&manifest_path)?.ok_or_else(|| MicError::NoWorkspace)?;

    if !json_output {
        println!(
            "unmounting {}/{} from {}",
            manifest.account,
            manifest.repository,
            mount_path.display()
        );
    }

    // Check for uncommitted changes
    let session_path = hif_dir.join("session.bin");
    if session_path.exists() {
        if json_output {
            return Err(MicError::Other(
                "Active session with uncommitted changes. Run 'hif session land' or 'hif session abandon' first.".to_string(),
            ));
        }

        println!();
        println!("warning: active session with uncommitted changes");
        println!("run 'hif session land' or 'hif session abandon' before unmounting");
        println!();

        // Ask for confirmation
        print!("continue anyway? [y/N] ");
        std::io::Write::flush(&mut std::io::stdout())?;

        let mut input = String::new();
        std::io::stdin().read_line(&mut input)?;

        if !input.trim().eq_ignore_ascii_case("y") {
            if !json_output {
                println!("unmount aborted");
            }
            return Ok(());
        }
    }

    // Remove the .hif directory
    fs::remove_dir_all(&hif_dir)?;

    // Optionally remove the entire mount directory if empty or if requested
    if std::env::args().any(|a| a == "--remove") {
        // Remove all files in the mount directory
        for entry in fs::read_dir(&mount_path)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                fs::remove_dir_all(&path)?;
            } else {
                fs::remove_file(&path)?;
            }
        }

        // Remove the mount directory itself
        fs::remove_dir(&mount_path)?;
        if json_output {
            output::print_ok(
                "unmount",
                UnmountOutput {
                    path: mount_path,
                    removed: true,
                },
            )?;
        } else {
            println!("removed '{}'", mount_path.display());
        }
    } else {
        if json_output {
            output::print_ok(
                "unmount",
                UnmountOutput {
                    path: mount_path,
                    removed: false,
                },
            )?;
        } else {
            println!("unmounted; files remain at '{}'", mount_path.display());
            println!("run 'hif unmount {} --remove' to remove files", cmd.path);
        }
    }

    Ok(())
}
