//! Mount command - mount repository as virtual filesystem.
//!
//! This command currently creates a local mirror from forge content.
#![allow(dead_code)]

use crate::cli::{parse_repository_ref, MountCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref, user_id_from_token};
use crate::grpc::{Endpoint, GrpcClient};
use std::fs;
use std::path::PathBuf;

/// Default NFS port.
pub const DEFAULT_PORT: u16 = 20490;

/// Run the mount command.
pub async fn run(cmd: MountCommand) -> Result<()> {
    let (organization, repository) = parse_repository_ref(&cmd.repository).ok_or_else(|| {
        MicError::InvalidRepositoryRef(format!(
            "Invalid repository reference '{}'. Use format: org/repository",
            cmd.repository
        ))
    })?;

    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);
    let user_id = user_id_from_token(&tokens.access_token);

    let mount_path = cmd.path.clone().unwrap_or_else(|| repository.to_string());
    let mount_path = PathBuf::from(&mount_path);

    println!(
        "Mounting {}/{} to {}...",
        organization,
        repository,
        mount_path.display()
    );

    if !mount_path.exists() {
        fs::create_dir_all(&mount_path)?;
    }

    let (tree, revision_hash) = fetch_tree(
        &client,
        &tokens.access_token,
        &user_id,
        organization,
        repository,
    )
    .await?;
    let file_count = sync_tree(
        &client,
        &tokens.access_token,
        &user_id,
        organization,
        repository,
        &revision_hash,
        &tree,
        &mount_path,
    )
    .await?;

    write_mount_metadata(&mount_path, &server, organization, repository)?;

    println!("Synced {} files to {}", file_count, mount_path.display());
    println!();
    println!("Note: This is a local mirror, not a live mount.");
    println!("Changes made locally are not auto-landed; use 'hif session land'.");

    Ok(())
}

/// Tree entry for mounting.
struct MountEntry {
    path: String,
    hash: String,
}

/// Fetch the tree from the forge.
async fn fetch_tree(
    client: &GrpcClient,
    access_token: &str,
    user_id: &str,
    organization: &str,
    repository: &str,
) -> Result<(Vec<MountEntry>, Vec<u8>)> {
    let repository = repository_ref(organization, repository);
    let head: pb::RepositoryHeadResponse = call(
        client,
        access_token,
        "/hif.v1.VersioningService/GetRepositoryHead",
        &pb::GetRepositoryHeadRequest {
            user_id: user_id.to_string(),
            repository: Some(repository.clone()),
        },
    )
    .await?;

    let revision_hash = head
        .head
        .as_ref()
        .map(|value| value.hash.clone())
        .unwrap_or_default();
    let tree: pb::TreeResponse = call(
        client,
        access_token,
        "/hif.v1.ContentService/GetTree",
        &pb::GetTreeRequest {
            user_id: user_id.to_string(),
            repository: Some(repository),
            revision_hash: revision_hash.clone(),
        },
    )
    .await?;

    Ok((
        tree.entries
            .into_iter()
            .map(|entry| MountEntry {
                path: entry.path,
                hash: entry.hash,
            })
            .collect::<Vec<_>>(),
        revision_hash,
    ))
}

/// Sync the tree to the local filesystem.
async fn sync_tree(
    client: &GrpcClient,
    access_token: &str,
    user_id: &str,
    organization: &str,
    repository: &str,
    revision_hash: &[u8],
    tree: &[MountEntry],
    mount_path: &PathBuf,
) -> Result<usize> {
    let mut synced = 0;

    for entry in tree {
        let file_path = mount_path.join(&entry.path);
        if let Some(parent) = file_path.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent)?;
            }
        }

        let content = fetch_file(
            client,
            access_token,
            user_id,
            organization,
            repository,
            &entry.path,
            revision_hash,
        )
        .await?;

        let should_write = match fs::read(&file_path) {
            Ok(existing) => existing != content,
            Err(_) => true,
        };

        if should_write {
            fs::write(&file_path, &content)?;
            synced += 1;
            println!("  {} ({})", entry.path, entry.hash);
        }
    }

    Ok(synced)
}

/// Fetch a file's content.
async fn fetch_file(
    client: &GrpcClient,
    access_token: &str,
    user_id: &str,
    organization: &str,
    repository: &str,
    path: &str,
    revision_hash: &[u8],
) -> Result<Vec<u8>> {
    let response: pb::PathResponse = call(
        client,
        access_token,
        "/hif.v1.ContentService/GetPath",
        &pb::GetPathRequest {
            user_id: user_id.to_string(),
            repository: Some(repository_ref(organization, repository)),
            revision_hash: revision_hash.to_vec(),
            path: path.to_string(),
        },
    )
    .await?;

    Ok(response.content)
}

/// Create a .hif directory in the mount path with repository metadata.
fn write_mount_metadata(
    mount_path: &PathBuf,
    server: &str,
    organization: &str,
    repository: &str,
) -> Result<()> {
    use crate::workspace::{WorkspaceManifest, HIF_DIR, MANIFEST_FILE};

    let hif_dir = mount_path.join(HIF_DIR);
    if !hif_dir.exists() {
        fs::create_dir_all(&hif_dir)?;
    }

    let manifest = WorkspaceManifest::new(server, organization, repository);
    let manifest_path = hif_dir.join(MANIFEST_FILE);
    manifest.save_to(&manifest_path)?;

    Ok(())
}
