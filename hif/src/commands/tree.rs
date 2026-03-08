//! Tree command - list directory contents from the forge.

use crate::cli::{parse_project_ref, TreeCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref, user_id_from_token};
use crate::grpc::{Endpoint, GrpcClient};
use crate::workspace::{parse_position, PositionOrLatest};
use std::collections::BTreeSet;

/// Run the tree command.
pub async fn run(cmd: TreeCommand) -> Result<()> {
    let (org, project) = parse_project_ref(&cmd.project).ok_or_else(|| {
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
        &tokens.access_token,
        "/hif.v1.ContentService/GetTree",
        &pb::GetTreeRequest {
            user_id,
            repository: Some(repository_ref(org, project)),
            revision_hash: position.unwrap_or_default(),
        },
    )
    .await?;

    let entries = response
        .entries
        .into_iter()
        .map(|entry| entry.path)
        .collect::<Vec<_>>();
    for entry in list_directory_entries(&entries, cmd.path.as_deref().unwrap_or("")) {
        println!("{}", entry);
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
