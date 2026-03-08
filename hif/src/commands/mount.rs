//! Mount command - mount project as virtual filesystem.
//!
//! This command currently creates a local mirror from forge content.
#![allow(dead_code)]

use crate::cli::{parse_project_ref, MountCommand};
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
    let (organization, project) = parse_project_ref(&cmd.project).ok_or_else(|| {
        MicError::InvalidProjectRef(format!(
            "Invalid project reference '{}'. Use format: org/project",
            cmd.project
        ))
    })?;

    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);
    let user_id = user_id_from_token(&tokens.access_token);

    let mount_path = cmd.path.clone().unwrap_or_else(|| project.to_string());
    let mount_path = PathBuf::from(&mount_path);

    println!(
        "Mounting {}/{} to {}...",
        organization,
        project,
        mount_path.display()
    );

    if !mount_path.exists() {
        fs::create_dir_all(&mount_path)?;
    }

    let (tree, position) = fetch_tree(
        &client,
        &tokens.access_token,
        &user_id,
        organization,
        project,
    )
    .await?;
    let file_count = sync_tree(
        &client,
        &tokens.access_token,
        &user_id,
        organization,
        project,
        position,
        &tree,
        &mount_path,
    )
    .await?;

    write_mount_metadata(&mount_path, &server, organization, project)?;

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
    project: &str,
) -> Result<(Vec<MountEntry>, u64)> {
    let repository = repository_ref(organization, project);
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

    let position = head.head.as_ref().map(|value| value.id).unwrap_or(0);
    let tree: pb::TreeResponse = call(
        client,
        access_token,
        "/hif.v1.ContentService/GetTree",
        &pb::GetTreeRequest {
            user_id: user_id.to_string(),
            repository: Some(repository),
            position,
            tree_hash: Vec::new(),
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
        position,
    ))
}

/// Sync the tree to the local filesystem.
async fn sync_tree(
    client: &GrpcClient,
    access_token: &str,
    user_id: &str,
    organization: &str,
    project: &str,
    position: u64,
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
            project,
            &entry.path,
            position,
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
    project: &str,
    path: &str,
    position: u64,
) -> Result<Vec<u8>> {
    let response: pb::PathResponse = call(
        client,
        access_token,
        "/hif.v1.ContentService/GetPath",
        &pb::GetPathRequest {
            user_id: user_id.to_string(),
            repository: Some(repository_ref(organization, project)),
            position,
            tree_hash: Vec::new(),
            path: path.to_string(),
        },
    )
    .await?;

    Ok(response.content)
}

/// Create a .hif directory in the mount path with project metadata.
fn write_mount_metadata(
    mount_path: &PathBuf,
    server: &str,
    organization: &str,
    project: &str,
) -> Result<()> {
    use crate::workspace::{WorkspaceManifest, HIF_DIR, MANIFEST_FILE};

    let hif_dir = mount_path.join(HIF_DIR);
    if !hif_dir.exists() {
        fs::create_dir_all(&hif_dir)?;
    }

    let manifest = WorkspaceManifest::new(server, organization, project);
    let manifest_path = hif_dir.join(MANIFEST_FILE);
    manifest.save_to(&manifest_path)?;

    Ok(())
}
