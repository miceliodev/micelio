//! Link command - link current directory to a repository.

use crate::cli::{parse_repository_ref, LinkCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::output;
use crate::workspace::manifest::Manifest;
use serde::Serialize;

#[derive(Serialize)]
pub(crate) struct LinkOutput {
    account: String,
    repository: String,
    server: String,
}

/// Run the link command.
pub async fn run(cmd: LinkCommand) -> Result<()> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;

    // Parse repository reference
    let (org, repository) = parse_repository_ref(&cmd.repository).ok_or_else(|| {
        MicError::InvalidRepositoryRef(format!(
            "Invalid repository reference '{}'. Use format: account/repository",
            cmd.repository
        ))
    })?;

    // Verify we're authenticated
    let _tokens = config::require_tokens()?;

    // Create workspace manifest in current directory
    let manifest = Manifest::new(&server, org, repository);
    manifest.save()?;

    if output::use_json() {
        output::print_ok(
            "link",
            LinkOutput {
                account: org.to_string(),
                repository: repository.to_string(),
                server: server.clone(),
            },
        )?;
    } else {
        output::set_success_message(format!(
            "Linked working tree to '{}/{}' (server {}).",
            org, repository, server
        ));
    }

    Ok(())
}
