//! Checkout command - create local workspace from a project.

use crate::cli::{parse_project_ref, CheckoutCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::workspace::WorkspaceManifest;
use std::fs;

/// Run the checkout command.
pub async fn run(cmd: CheckoutCommand) -> Result<()> {
    // Parse project reference
    let (org, project) = parse_project_ref(&cmd.project).ok_or_else(|| {
        MicError::InvalidProjectRef(format!(
            "Invalid project reference '{}'. Use format: org/project",
            cmd.project
        ))
    })?;

    let config = Config::load()?;
    let server = config.get_default_server().ok_or(MicError::NoDefaultServer)?;
    let _tokens = config::require_tokens()?;

    // Determine target directory
    let target_path = cmd.path.unwrap_or_else(|| project.to_string());

    // Create directory if it doesn't exist
    if !std::path::Path::new(&target_path).exists() {
        fs::create_dir_all(&target_path)?;
    }

    // Change to target directory
    std::env::set_current_dir(&target_path)?;

    // Create workspace manifest
    let manifest = WorkspaceManifest::new(server, org, project);
    manifest.save()?;

    println!("Checked out {}/{} to {}", org, project, target_path);
    println!();
    println!("Start working:");
    println!("  cd {}", target_path);
    println!("  mic session start \"your goal\"");

    Ok(())
}
