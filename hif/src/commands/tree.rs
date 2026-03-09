//! Tree command - list directory contents from the forge.

use crate::cli::{parse_repository_ref, TreeCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;
use crate::workspace::{parse_position, PositionOrLatest};
use std::collections::BTreeSet;

/// Run the tree command.
pub async fn run(cmd: TreeCommand) -> Result<()> {
    let (org, repository) = parse_repository_ref(&cmd.repository).ok_or_else(|| {
        MicError::InvalidRepositoryRef(format!(
            "Invalid repository reference '{}'. Use format: account/repository",
            cmd.repository
        ))
    })?;

    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let position = if let Some(ref pos_str) = cmd.r#ref {
        match parse_position(pos_str) {
            Some(PositionOrLatest::Revision(value)) => Some(value),
            Some(PositionOrLatest::Latest) => None,
            None => return Err(MicError::Other("Invalid revision format".to_string())),
        }
    } else {
        None
    };

    let response: pb::TreeResponse = call(
        &client,
        "/hif.v1.ContentService/GetTree",
        &pb::GetTreeRequest {
            repository: Some(repository_ref(org, repository)),
            revision_hash: position.unwrap_or_default(),
        },
    )
    .await?;

    let entries = response
        .entries
        .into_iter()
        .map(|entry| entry.path)
        .collect::<Vec<_>>();

    let listed = list_directory_entries(&entries, cmd.path.as_deref().unwrap_or(""));
    if output::use_json() {
        output::print_ok(
            "tree",
            serde_json::json!({
                "repository": cmd.repository,
                "path": cmd.path.unwrap_or_default(),
                "entries": listed
            }),
        )?;
    } else {
        for entry in listed {
            println!("{}", entry);
        }
    }

    Ok(())
}

fn list_directory_entries(entries: &[String], directory: &str) -> Vec<String> {
    let normalized = directory.trim_matches('/');
    let prefix = if normalized.is_empty() {
        String::new()
    } else {
        format!("{}/", normalized)
    };

    let mut directories = BTreeSet::new();
    let mut files = BTreeSet::new();

    for path in entries {
        if !path.starts_with(&prefix) {
            continue;
        }

        let remainder = &path[prefix.len()..];
        if remainder.is_empty() {
            continue;
        }

        if let Some((dir, _)) = remainder.split_once('/') {
            if !dir.is_empty() {
                directories.insert(format!("{}/", dir));
            }
        } else {
            files.insert(remainder.to_string());
        }
    }

    directories.into_iter().chain(files).collect::<Vec<_>>()
}
