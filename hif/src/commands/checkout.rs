//! Checkout command - create local workspace from a repository.

use crate::cli::{parse_repository_ref, CheckoutCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::output;
use crate::workspace::WorkspaceManifest;
use serde::Serialize;
use std::fs;
use std::path::PathBuf;

#[derive(Serialize)]
pub(crate) struct CheckoutOutput {
    account: String,
    repository: String,
    path: String,
    server: String,
}

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
    let target_dir = PathBuf::from(&target_path);

    // Create directory if it doesn't exist
    if !target_dir.exists() {
        fs::create_dir_all(&target_dir)?;
    }

    // Create workspace manifest in the checkout target without mutating process CWD.
    let manifest = WorkspaceManifest::new(&server, org, repository);
    let manifest_path = target_dir
        .join(crate::workspace::HIF_DIR)
        .join(crate::workspace::MANIFEST_FILE);
    manifest.save_to(&manifest_path)?;

    if output::use_json() {
        output::print_ok(
            "checkout",
            CheckoutOutput {
                account: org.to_string(),
                repository: repository.to_string(),
                path: target_path.clone(),
                server: server.clone(),
            },
        )?;
    } else {
        println!("Checked out {}/{} to {}", org, repository, target_path);
        println!();
        println!("Start working:");
        println!("  cd {}", target_path);
        println!("  hif session start \"your goal\"");
    }

    Ok(())
}
