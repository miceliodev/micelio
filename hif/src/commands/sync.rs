//! Sync command - sync workspace with latest upstream changes.

use crate::cli::SyncCommand;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;
use crate::workspace::{session::Session, WorkspaceManifest};
use serde::Serialize;
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
    /// New revision hash after sync
    pub revision_hash: Vec<u8>,
}

#[derive(Serialize)]
pub(crate) struct SyncOutput {
    account: String,
    repository: String,
    strategy: String,
    updated: Vec<String>,
    conflicts: Vec<String>,
    revision: String,
}

/// Run the sync command.
pub async fn run(cmd: SyncCommand) -> Result<()> {
    let strategy = MergeStrategy::parse(&cmd.strategy)
        .ok_or_else(|| MicError::Other(format!("Invalid strategy: {}", cmd.strategy)))?;
    let json_output = output::use_json();

    if json_output && strategy == MergeStrategy::Interactive {
        return Err(MicError::Other(
            "Interactive sync is not supported with --json. Use --strategy ours|theirs."
                .to_string(),
        ));
    }

    // Check if we're in a workspace
    let mut manifest = WorkspaceManifest::load()?.ok_or(MicError::NoWorkspace)?;

    if !json_output {
        println!(
            "syncing {}/{} from {}",
            manifest.account, manifest.repository, manifest.server
        );
    }

    let result = sync_workspace(&mut manifest, strategy).await?;

    // Report results
    if json_output {
        output::print_ok(
            "sync",
            SyncOutput {
                account: manifest.account.clone(),
                repository: manifest.repository.clone(),
                strategy: cmd.strategy,
                updated: result.updated,
                conflicts: result.conflicts,
                revision: format_revision_hash(&result.revision_hash),
            },
        )?;
    } else {
        if result.updated.is_empty() && result.conflicts.is_empty() {
            println!("already up to date");
        } else {
            if !result.updated.is_empty() {
                println!("\nupdated {} files:", result.updated.len());
                for path in &result.updated {
                    println!("  U {}", path);
                }
            }

            if !result.conflicts.is_empty() {
                println!("\nconflicts in {} files:", result.conflicts.len());
                for path in &result.conflicts {
                    println!("  C {}", path);
                }
                println!("\nresolve conflicts and run 'hif session land'");
            }
        }

        println!("\nrevision {}", format_revision_hash(&result.revision_hash));
    }

    Ok(())
}

/// Perform the sync operation.
async fn sync_workspace(
    manifest: &mut WorkspaceManifest,
    strategy: MergeStrategy,
) -> Result<SyncResult> {
    let endpoint = Endpoint::parse(&manifest.server)?;
    let client = GrpcClient::new(endpoint);

    // Fetch latest tree from forge
    let (upstream_tree, revision_hash) =
        fetch_upstream_tree(&client, &manifest.account, &manifest.repository).await?;

    // Get local session changes if any
    let local_changes = if let Some(state) = Session::load()? {
        state
            .files
            .iter()
            .map(|f| (f.path.clone(), f.clone()))
            .collect::<HashMap<_, _>>()
    } else {
        HashMap::new()
    };

    // Build current local tree from manifest
    let local_tree: HashMap<String, String> = manifest
        .entries
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
                        &manifest.account,
                        &manifest.repository,
                        path,
                        Some(revision_hash.as_slice()),
                    )
                    .await?;

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
                                &manifest.account,
                                &manifest.repository,
                                path,
                                Some(revision_hash.as_slice()),
                            )
                            .await?;

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
                &manifest.account,
                &manifest.repository,
                path,
                Some(revision_hash.as_slice()),
            )
            .await?;

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
                        if !output::use_json() {
                            println!("file '{}' was deleted upstream but modified locally", path);
                        }
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
    manifest.tree_hash = format_revision_hash(&revision_hash);
    manifest.save()?;

    Ok(SyncResult {
        updated,
        conflicts,
        revision_hash,
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
    print!("conflict in '{}': [o]urs / [t]heirs / [s]kip? ", path);
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
    organization: &str,
    repository: &str,
) -> Result<(HashMap<String, String>, Vec<u8>)> {
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

    let tree_response: pb::TreeResponse = call(
        client,
        "/hif.v1.ContentService/GetTree",
        &pb::GetTreeRequest {
            repository: Some(repository),
            revision_hash: revision_hash.clone(),
        },
    )
    .await?;

    let tree = tree_response
        .entries
        .into_iter()
        .map(|entry| (entry.path, entry.hash))
        .collect();

    Ok((tree, revision_hash))
}

/// Fetch file content from the forge.
async fn fetch_file_content(
    client: &GrpcClient,
    organization: &str,
    repository: &str,
    path: &str,
    revision_hash: Option<&[u8]>,
) -> Result<String> {
    let response: pb::PathResponse = call(
        client,
        "/hif.v1.ContentService/GetPath",
        &pb::GetPathRequest {
            repository: Some(repository_ref(organization, repository)),
            revision_hash: revision_hash.map(|hash| hash.to_vec()).unwrap_or_default(),
            path: path.to_string(),
        },
    )
    .await?;

    Ok(String::from_utf8_lossy(&response.content).to_string())
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

fn format_revision_hash(hash: &[u8]) -> String {
    if hash.is_empty() {
        return "0000000000000000000000000000000000000000000000000000000000000000".to_string();
    }

    hash.iter()
        .map(|byte| format!("{:02x}", byte))
        .collect::<String>()
}
