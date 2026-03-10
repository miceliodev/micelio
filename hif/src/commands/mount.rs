//! Mount command - mount repository as virtual filesystem.
//!
//! This command currently creates a local mirror from forge content.
#![allow(dead_code)]

use crate::cli::{parse_repository_ref, MountCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;
use serde::Serialize;
use std::fs;
use std::path::PathBuf;

/// Default NFS port.
pub const DEFAULT_PORT: u16 = 20490;

#[derive(Serialize)]
pub(crate) struct MountOutput {
    account: String,
    repository: String,
    path: PathBuf,
    synced_files: usize,
    revision: String,
}

/// Run the mount command.
pub async fn run(cmd: MountCommand) -> Result<()> {
    let (organization, repository) = parse_repository_ref(&cmd.repository).ok_or_else(|| {
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

    if !json_output {
        println!(
            "Mounting {}/{} to {}...",
            organization,
            repository,
            mount_path.display()
        );
    }

    if !mount_path.exists() {
        fs::create_dir_all(&mount_path)?;
    }

    let (tree, revision_hash) = fetch_tree(&client, organization, repository).await?;
    let file_count = sync_tree(
        &client,
        organization,
        repository,
        &revision_hash,
        &tree,
        &mount_path,
        json_output,
    )
    .await?;

    write_mount_metadata(&mount_path, &server, organization, repository)?;

    if json_output {
        let revision = revision_hash
            .iter()
            .map(|byte| format!("{:02x}", byte))
            .collect::<String>();

        output::print_ok(
            "mount",
            MountOutput {
                account: organization.to_string(),
                repository: repository.to_string(),
                path: mount_path,
                synced_files: file_count,
                revision,
            },
        )?;
    } else {
        println!("Synced {} files to {}", file_count, mount_path.display());
        println!();
        println!("Note: This is a local mirror, not a live mount.");
        println!("Changes made locally are not auto-landed; use 'hif session land'.");
    }

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
    organization: &str,
    repository: &str,
) -> Result<(Vec<MountEntry>, Vec<u8>)> {
    let repository = repository_ref(organization, repository);
    let head: pb::RepositoryHeadResponse = call(
        client,
        "/hif.v1.VersioningService/GetRepositoryHead",
        &pb::GetRepositoryHeadRequest {
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
        "/hif.v1.ContentService/GetTree",
        &pb::GetTreeRequest {
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
    organization: &str,
    repository: &str,
    revision_hash: &[u8],
    tree: &[MountEntry],
    mount_path: &PathBuf,
    json_output: bool,
) -> Result<usize> {
    let mut synced = 0;

    for entry in tree {
        let file_path = mount_path.join(&entry.path);
        if let Some(parent) = file_path.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent)?;
            }
        }

        let content =
            fetch_file(client, organization, repository, &entry.path, revision_hash).await?;

        let should_write = match fs::read(&file_path) {
            Ok(existing) => existing != content,
            Err(_) => true,
        };

        if should_write {
            fs::write(&file_path, &content)?;
            synced += 1;
            if !json_output {
                println!("  {} ({})", entry.path, entry.hash);
            }
        }
    }

    Ok(synced)
}

/// Fetch a file's content.
async fn fetch_file(
    client: &GrpcClient,
    organization: &str,
    repository: &str,
    path: &str,
    revision_hash: &[u8],
) -> Result<Vec<u8>> {
    let response: pb::PathResponse = call(
        client,
        "/hif.v1.ContentService/GetPath",
        &pb::GetPathRequest {
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
