//! Link command - link current directory to a project.

use crate::cli::{parse_project_ref, LinkCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::workspace::manifest::Manifest;

/// Run the link command.
pub async fn run(cmd: LinkCommand) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;

    // Parse project reference
    let (org, project) = parse_project_ref(&cmd.project).ok_or_else(|| {
        MicError::InvalidProjectRef(format!(
            "Invalid project reference '{}'. Use format: org/project",
            cmd.project
        ))
    })?;

    // Verify we're authenticated
    let _tokens = config::require_tokens()?;

    // Create workspace manifest in current directory
    let manifest = Manifest::new(&server, org, project);
    manifest.save()?;

    println!("Linked to {}/{}", org, project);
    println!("Server: {}", server);

    Ok(())
}
