//! Sync command - sync workspace with latest upstream changes.

use crate::cli::SyncCommand;
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::{Endpoint, GrpcClient};
use crate::grpc::client::{read_field, read_string, read_varint_value, write_length_delimited};
use crate::workspace::{WorkspaceManifest, session::Session};
use std::collections::HashMap;
use std::fs;
use std::io::{self, Write};

/// Merge strategy for sync.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MergeStrategy {
    /// Keep local changes, discard upstream
    Ours,
    /// Keep upstream changes, discard local
    Theirs,
    /// Interactive resolution for each conflict
    Interactive,
}

impl MergeStrategy {
    pub fn parse(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "ours" => Some(MergeStrategy::Ours),
            "theirs" => Some(MergeStrategy::Theirs),
            "interactive" => Some(MergeStrategy::Interactive),
            _ => None,
        }
    }
}

/// Sync result.
#[derive(Debug)]
pub struct SyncResult {
    /// Files updated from upstream
    pub updated: Vec<String>,
    /// Files with conflicts
    pub conflicts: Vec<String>,
    /// New position after sync
    pub position: u64,
}

/// Run the sync command.
pub async fn run(cmd: SyncCommand) -> Result<()> {
    let strategy = MergeStrategy::parse(&cmd.strategy)
        .ok_or_else(|| MicError::Other(format!("Invalid strategy: {}", cmd.strategy)))?;

    // Check if we're in a workspace
    let mut manifest = WorkspaceManifest::load()?
        .ok_or(MicError::NoWorkspace)?;

    println!("Syncing {}/{} from {}...", manifest.account, manifest.project, manifest.server);

    let result = sync_workspace(&mut manifest, strategy).await?;

    // Report results
    if result.updated.is_empty() && result.conflicts.is_empty() {
        println!("Already up to date.");
    } else {
        if !result.updated.is_empty() {
            println!("\nUpdated {} files:", result.updated.len());
            for path in &result.updated {
                println!("  U {}", path);
            }
        }

        if !result.conflicts.is_empty() {
            println!("\nConflicts in {} files:", result.conflicts.len());
            for path in &result.conflicts {
                println!("  C {}", path);
            }
            println!("\nResolve conflicts and run 'mic session land' to continue.");
        }
    }

    println!("\nSynced to position @{}", result.position);

    Ok(())
}

/// Perform the sync operation.
async fn sync_workspace(manifest: &mut WorkspaceManifest, strategy: MergeStrategy) -> Result<SyncResult> {
    let _config = Config::load()?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&manifest.server)?;
    let client = GrpcClient::new(endpoint);

    // Fetch latest tree from forge
    let (upstream_tree, position) = fetch_upstream_tree(
        &client,
        &tokens.access_token,
        &manifest.account,
        &manifest.project,
    ).await?;

    // Get local session changes if any
    let local_changes = if let Some(state) = Session::load()? {
        state.files.iter()
            .map(|f| (f.path.clone(), f.clone()))
            .collect::<HashMap<_, _>>()
    } else {
        HashMap::new()
    };

    // Build current local tree from manifest
    let local_tree: HashMap<String, String> = manifest.entries
        .iter()
        .map(|e| (e.path.clone(), e.hash.clone()))
        .collect();

    let mut updated = Vec::new();
    let mut conflicts = Vec::new();

    // Process each upstream file
    for (path, upstream_hash) in &upstream_tree {
        let local_hash = local_tree.get(path);
        let has_local_change = local_changes.contains_key(path);

        if local_hash == Some(upstream_hash) {
            // No change upstream for this file
            continue;
        }

        if has_local_change {
            // Conflict: local change and upstream change
            match strategy {
                MergeStrategy::Ours => {
                    // Keep local, ignore upstream
                    conflicts.push(path.clone());
                }
                MergeStrategy::Theirs => {
                    // Take upstream, discard local
                    let content = fetch_file_content(
                        &client,
                        &tokens.access_token,
                        &manifest.account,
                        &manifest.project,
                        path,
                        Some(position),
                    ).await?;
                    
                    write_file(path, &content)?;
                    updated.push(path.clone());
                }
                MergeStrategy::Interactive => {
                    // Prompt user for each conflict
                    let resolution = prompt_conflict_resolution(path)?;
                    match resolution {
                        ConflictResolution::Ours => {
                            conflicts.push(path.clone());
                        }
                        ConflictResolution::Theirs => {
                            let content = fetch_file_content(
                                &client,
                                &tokens.access_token,
                                &manifest.account,
                                &manifest.project,
                                path,
                                Some(position),
                            ).await?;
                            
                            write_file(path, &content)?;
                            updated.push(path.clone());
                        }
                        ConflictResolution::Skip => {
                            conflicts.push(path.clone());
                        }
                    }
                }
            }
        } else {
            // No local change, take upstream
            let content = fetch_file_content(
                &client,
                &tokens.access_token,
                &manifest.account,
                &manifest.project,
                path,
                Some(position),
            ).await?;
            
            write_file(path, &content)?;
            updated.push(path.clone());
        }
    }

    // Check for files deleted upstream
    for path in local_tree.keys() {
        if !upstream_tree.contains_key(path) {
            let has_local_change = local_changes.contains_key(path);

            if has_local_change {
                // Conflict: file deleted upstream but modified locally
                match strategy {
                    MergeStrategy::Ours => {
                        conflicts.push(path.clone());
                    }
                    MergeStrategy::Theirs => {
                        delete_file(path)?;
                        updated.push(format!("{} (deleted)", path));
                    }
                    MergeStrategy::Interactive => {
                        println!("File '{}' was deleted upstream but modified locally.", path);
                        let resolution = prompt_conflict_resolution(path)?;
                        match resolution {
                            ConflictResolution::Ours => {
                                conflicts.push(path.clone());
                            }
                            ConflictResolution::Theirs => {
                                delete_file(path)?;
                                updated.push(format!("{} (deleted)", path));
                            }
                            ConflictResolution::Skip => {
                                conflicts.push(path.clone());
                            }
                        }
                    }
                }
            } else {
                // No local change, delete the file
                delete_file(path)?;
                updated.push(format!("{} (deleted)", path));
            }
        }
    }

    // Update manifest with new tree
    manifest.entries.clear();
    for (path, hash) in &upstream_tree {
        manifest.entries.push(crate::workspace::WorkspaceEntry {
            path: path.clone(),
            hash: hash.clone(),
            mode: 0o100644,
            size: 0,
        });
    }
    manifest.tree_hash = format!("position:{}", position);
    manifest.save()?;

    Ok(SyncResult {
        updated,
        conflicts,
        position,
    })
}

/// Conflict resolution choice.
#[derive(Debug, Clone, Copy)]
enum ConflictResolution {
    Ours,
    Theirs,
    Skip,
}

/// Prompt user for conflict resolution.
fn prompt_conflict_resolution(path: &str) -> Result<ConflictResolution> {
    print!("Conflict in '{}'. [o]urs / [t]heirs / [s]kip? ", path);
    io::stdout().flush()?;

    let mut input = String::new();
    io::stdin().read_line(&mut input)?;

    match input.trim().to_lowercase().as_str() {
        "o" | "ours" => Ok(ConflictResolution::Ours),
        "t" | "theirs" => Ok(ConflictResolution::Theirs),
        "s" | "skip" | "" => Ok(ConflictResolution::Skip),
        _ => Ok(ConflictResolution::Skip),
    }
}

/// Fetch the upstream tree.
async fn fetch_upstream_tree(
    client: &GrpcClient,
    token: &str,
    account: &str,
    project: &str,
) -> Result<(HashMap<String, String>, u64)> {
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

    let mut tree = HashMap::new();
    let mut position = 0u64;
    let mut pos = 0;

    while pos < response.len() {
        if let Some((field_number, _, field_data)) = read_field(&response, &mut pos) {
            match field_number {
                1 => {
                    // Tree entry
                    let (path, hash) = parse_tree_entry(field_data);
                    if !path.is_empty() {
                        tree.insert(path, hash);
                    }
                }
                2 => {
                    // Position
                    position = read_varint_value(field_data);
                }
                _ => {}
            }
        }
    }

    Ok((tree, position))
}

/// Parse a tree entry from protobuf.
fn parse_tree_entry(data: &[u8]) -> (String, String) {
    let mut pos = 0;
    let mut path = String::new();
    let mut hash = String::new();

    while pos < data.len() {
        if let Some((field_number, _, field_data)) = read_field(data, &mut pos) {
            match field_number {
                1 => path = read_string(field_data),
                2 => hash = read_string(field_data),
                _ => {}
            }
        }
    }

    (path, hash)
}

/// Fetch file content from the forge.
async fn fetch_file_content(
    client: &GrpcClient,
    token: &str,
    account: &str,
    project: &str,
    path: &str,
    position: Option<u64>,
) -> Result<String> {
    use crate::grpc::client::write_varint_field;

    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, account.as_bytes());
    write_length_delimited(&mut request, 2, project.as_bytes());
    write_length_delimited(&mut request, 3, path.as_bytes());
    if let Some(pos) = position {
        write_varint_field(&mut request, 4, pos);
    }

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
                return Ok(read_string(field_data));
            }
        }
    }

    Ok(String::new())
}

/// Write content to a file.
fn write_file(path: &str, content: &str) -> Result<()> {
    // Ensure parent directory exists
    if let Some(parent) = std::path::Path::new(path).parent() {
        if !parent.as_os_str().is_empty() && !parent.exists() {
            fs::create_dir_all(parent)?;
        }
    }

    fs::write(path, content)?;
    Ok(())
}

/// Delete a file.
fn delete_file(path: &str) -> Result<()> {
    if std::path::Path::new(path).exists() {
        fs::remove_file(path)?;
    }
    Ok(())
}
