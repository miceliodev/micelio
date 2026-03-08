//! Checkout command - create local workspace from a repository.

use crate::cli::{parse_repository_ref, CheckoutCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::workspace::WorkspaceManifest;
use std::fs;

/// Run the checkout command.
pub async fn run(cmd: CheckoutCommand) -> Result<()> {
    // Parse repository reference
    let (org, repository) = parse_repository_ref(&cmd.repository).ok_or_else(|| {
        MicError::InvalidRepositoryRef(format!(
            "Invalid repository reference '{}'. Use format: account/repository",
            cmd.repository
        ))
    })?;

    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let _tokens = config::require_tokens()?;

    // Determine target directory
    let target_path = cmd.path.unwrap_or_else(|| repository.to_string());

    // Create directory if it doesn't exist
    if !std::path::Path::new(&target_path).exists() {
        fs::create_dir_all(&target_path)?;
    }

    // Change to target directory
    std::env::set_current_dir(&target_path)?;

    // Create workspace manifest
    let manifest = WorkspaceManifest::new(&server, org, repository);
    manifest.save()?;

    println!("Checked out {}/{} to {}", org, repository, target_path);
    println!();
    println!("Start working:");
    println!("  cd {}", target_path);
    println!("  hif session start \"your goal\"");

    Ok(())
}
