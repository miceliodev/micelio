//! Checkout command - create local workspace from a repository.

use crate::cli::{parse_repository_ref, CheckoutCommand};
use crate::commands::sync::{fetch_file_content, fetch_upstream_tree, format_revision_hash};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;
use crate::workspace::{WorkspaceEntry, WorkspaceManifest};
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

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

    if directory_has_user_files(&target_dir)? {
        return Err(MicError::Other(format!(
            "Checkout target '{}' is not empty. Use an empty directory or pass --path to a new location.",
            target_dir.display()
        )));
    }

    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    // Create workspace manifest in the checkout target without mutating process CWD.
    let mut manifest = WorkspaceManifest::new(&server, org, repository);
    materialize_workspace(&client, org, repository, &target_dir, &mut manifest).await?;

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
        output::set_success_message(format!(
            "Checked out '{}/{}' to '{}'.",
            org, repository, target_path
        ));
        output::add_next_step(format!("cd {}", target_path));
        output::add_next_step("hif session start \"goal\"");
    }

    Ok(())
}

async fn materialize_workspace(
    client: &GrpcClient,
    organization: &str,
    repository: &str,
    target_dir: &Path,
    manifest: &mut WorkspaceManifest,
) -> Result<()> {
    let upstream = fetch_upstream_tree(client, organization, repository).await?;

    for (path, hash) in upstream.entries.iter() {
        let content = fetch_file_content(
            client,
            organization,
            repository,
            path,
            Some(&upstream.revision_hash),
        )
        .await?;

        let destination = target_dir.join(path);
        write_file_at_path(&destination, &content)?;

        manifest.upsert_entry(WorkspaceEntry {
            path: path.clone(),
            hash: hash.clone(),
            mode: 0o100644,
            size: content.len() as u64,
        });
    }

    manifest
        .entries
        .sort_by(|left, right| left.path.cmp(&right.path));
    manifest.tree_hash = format_revision_hash(&upstream.revision_hash);

    Ok(())
}

fn write_file_at_path(path: &Path, content: &str) -> Result<()> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() && !parent.exists() {
            fs::create_dir_all(parent)?;
        }
    }

    fs::write(path, content)?;
    Ok(())
}

fn directory_has_user_files(path: &Path) -> Result<bool> {
    for entry in fs::read_dir(path)? {
        let entry = entry?;
        if entry.file_name() != crate::workspace::HIF_DIR {
            return Ok(true);
        }
    }

    Ok(false)
}

#[cfg(test)]
mod tests {
    use crate::commands::ui_test_support::assert_output_snapshot;

    #[test]
    fn ui_snapshot_checkout_requires_auth() {
        assert_output_snapshot(
            &["checkout", "acme/repo"],
            1,
            "",
            "error: Not authenticated. Run 'hif auth login' first.\n",
        );
    }
}
