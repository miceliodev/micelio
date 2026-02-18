//! Mount command - mount project as virtual filesystem.
//!
//! This module provides virtual filesystem mounting for mic projects.
//! Currently implemented as a simple local mirror with watch capability.
//! Full FUSE/NFS support would require platform-specific code.
#![allow(dead_code)]

use crate::cli::{parse_project_ref, MountCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::client::{read_field, read_string, read_varint_value, write_length_delimited};
use crate::grpc::{Endpoint, GrpcClient};

use std::fs;
use std::path::PathBuf;

/// Default NFS port.
pub const DEFAULT_PORT: u16 = 20490;

/// Run the mount command.
pub async fn run(cmd: MountCommand) -> Result<()> {
    // Parse project reference
    let (org, project) = parse_project_ref(&cmd.project).ok_or_else(|| {
        MicError::InvalidProjectRef(format!(
            "Invalid project reference '{}'. Use format: org/project",
            cmd.project
        ))
    })?;

    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;

    let mount_path = cmd.path.clone().unwrap_or_else(|| project.to_string());
    let mount_path = PathBuf::from(&mount_path);

    println!("Mounting {}/{} to {}...", org, project, mount_path.display());

    // Create mount directory
    if !mount_path.exists() {
        fs::create_dir_all(&mount_path)?;
    }

    // Fetch and sync the tree
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let tree = fetch_tree(&client, &tokens.access_token, org, &project).await?;
    let file_count = sync_tree(&client, &tokens.access_token, org, &project, &tree, &mount_path).await?;

    println!("Synced {} files to {}", file_count, mount_path.display());
    println!();
    println!("Note: This is a simple sync, not a live mount.");
    println!("Changes made locally will need to be pushed via 'mic session land'.");
    println!();
    println!("For live mounting with watch mode, run:");
    println!("  mic mount {} --watch", cmd.project);

    // If watch mode, start watching for changes
    if std::env::args().any(|a| a == "--watch") {
        println!();
        println!("Watch mode is not yet implemented.");
        println!("This would monitor for upstream changes and sync automatically.");
    }

    Ok(())
}

/// Tree entry for mounting.
struct MountEntry {
    path: String,
    is_dir: bool,
    hash: String,
    size: u64,
}

/// Fetch the tree from the forge.
async fn fetch_tree(
    client: &GrpcClient,
    token: &str,
    account: &str,
    project: &str,
) -> Result<Vec<MountEntry>> {
    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, account.as_bytes());
    write_length_delimited(&mut request, 2, project.as_bytes());

    let response = client
        .unary_call(
            "/micelio.content.v1.ContentService/ListTree",
            &request,
            Some(token),
        )
        .await?;

    let mut entries = Vec::new();
    let mut pos = 0;

    while pos < response.len() {
        if let Some((field_number, _, field_data)) = read_field(&response, &mut pos) {
            if field_number == 1 {
                let entry = parse_mount_entry(field_data);
                entries.push(entry);
            }
        }
    }

    Ok(entries)
}

/// Parse a tree entry for mounting.
fn parse_mount_entry(data: &[u8]) -> MountEntry {
    let mut pos = 0;
    let mut path = String::new();
    let mut hash = String::new();
    let mut is_dir = false;
    let mut size = 0u64;

    while pos < data.len() {
        if let Some((field_number, _, field_data)) = read_field(data, &mut pos) {
            match field_number {
                1 => path = read_string(field_data),
                2 => hash = read_string(field_data),
                3 => is_dir = read_varint_value(field_data) != 0,
                4 => size = read_varint_value(field_data),
                _ => {}
            }
        }
    }

    MountEntry { path, is_dir, hash, size }
}

/// Sync the tree to the local filesystem.
async fn sync_tree(
    client: &GrpcClient,
    token: &str,
    account: &str,
    project: &str,
    tree: &[MountEntry],
    mount_path: &PathBuf,
) -> Result<usize> {
    let mut synced = 0;

    // First, create all directories
    for entry in tree {
        if entry.is_dir {
            let dir_path = mount_path.join(&entry.path);
            if !dir_path.exists() {
                fs::create_dir_all(&dir_path)?;
            }
        }
    }

    // Then, sync all files
    for entry in tree {
        if entry.is_dir {
            continue;
        }

        let file_path = mount_path.join(&entry.path);

        // Check if file already exists with same hash
        if file_path.exists() {
            // For simplicity, we just check size
            // A full implementation would check content hash
            if let Ok(metadata) = fs::metadata(&file_path) {
                if metadata.len() == entry.size {
                    continue;
                }
            }
        }

        // Ensure parent directory exists
        if let Some(parent) = file_path.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent)?;
            }
        }

        // Fetch file content
        let content = fetch_file(client, token, account, project, &entry.path).await?;

        // Write file
        fs::write(&file_path, content)?;
        synced += 1;

        println!("  {} ({} bytes)", entry.path, entry.size);
    }

    Ok(synced)
}

/// Fetch a file's content.
async fn fetch_file(
    client: &GrpcClient,
    token: &str,
    account: &str,
    project: &str,
    path: &str,
) -> Result<Vec<u8>> {
    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, account.as_bytes());
    write_length_delimited(&mut request, 2, project.as_bytes());
    write_length_delimited(&mut request, 3, path.as_bytes());

    let response = client
        .unary_call(
            "/micelio.content.v1.ContentService/ReadFile",
            &request,
            Some(token),
        )
        .await?;

    // Parse response
    let mut pos = 0;
    while pos < response.len() {
        if let Some((field_number, _, field_data)) = read_field(&response, &mut pos) {
            if field_number == 1 {
                return Ok(field_data.to_vec());
            }
        }
    }

    Ok(Vec::new())
}

/// Create a .mic directory in the mount path with project metadata.
fn write_mount_metadata(mount_path: &PathBuf, server: &str, account: &str, project: &str) -> Result<()> {
    use crate::workspace::{WorkspaceManifest, MIC_DIR, MANIFEST_FILE};

    let mic_dir = mount_path.join(MIC_DIR);
    if !mic_dir.exists() {
        fs::create_dir_all(&mic_dir)?;
    }

    let manifest = WorkspaceManifest::new(server, account, project);
    let manifest_path = mic_dir.join(MANIFEST_FILE);
    manifest.save_to(&manifest_path)?;

    Ok(())
}
