//! Diff command - show changes between two revisions.

use crate::cli::{parse_repository_ref, DiffCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::workspace::{parse_position, PositionOrLatest};
use colored::Colorize;
use std::collections::BTreeMap;

/// Run the diff command.
pub async fn run(cmd: DiffCommand) -> Result<()> {
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

    let from_revision_hash = match parse_position(&cmd.from) {
        Some(PositionOrLatest::Revision(revision_hash)) => revision_hash,
        Some(PositionOrLatest::Latest) => {
            return Err(MicError::Other(
                "The FROM revision must be explicit (hex hash).".to_string(),
            ))
        }
        None => return Err(MicError::Other("Invalid FROM revision".to_string())),
    };

    let to_revision_hash = if let Some(ref to) = cmd.to {
        match parse_position(to) {
            Some(PositionOrLatest::Revision(revision_hash)) => Some(revision_hash),
            Some(PositionOrLatest::Latest) => None,
            None => return Err(MicError::Other("Invalid TO revision".to_string())),
        }
    } else {
        None
    };

    let response: pb::DiffResponse = call(
        &client,
        "/hif.v1.ContentService/Diff",
        &pb::DiffRequest {
            repository: Some(repository_ref(org, repository)),
            from_revision_hash,
            to_revision_hash: to_revision_hash.unwrap_or_default(),
            path_prefix: String::new(),
        },
    )
    .await?;

    let changes = summarize_changes(&response.hunks);
    for (path, change_type) in changes {
        match change_type {
            ChangeType::Added => println!("{} {}", "A".green(), path.green()),
            ChangeType::Deleted => println!("{} {}", "D".red(), path.red()),
            ChangeType::Modified => println!("{} {}", "M".yellow(), path.yellow()),
        }
    }

    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ChangeType {
    Added,
    Deleted,
    Modified,
}

fn summarize_changes(hunks: &[pb::DiffHunk]) -> BTreeMap<String, ChangeType> {
    let mut changes = BTreeMap::new();

    for hunk in hunks {
        let next = classify_hunk(hunk);
        changes
            .entry(hunk.path.clone())
            .and_modify(|existing| *existing = merge_change_types(*existing, next))
            .or_insert(next);
    }

    changes
}

fn classify_hunk(hunk: &pb::DiffHunk) -> ChangeType {
    let has_old = !hunk.old_line.is_empty();
    let has_new = !hunk.new_line.is_empty();

    match (has_old, has_new) {
        (false, true) => ChangeType::Added,
        (true, false) => ChangeType::Deleted,
        _ => ChangeType::Modified,
    }
}

fn merge_change_types(existing: ChangeType, next: ChangeType) -> ChangeType {
    if existing == ChangeType::Modified || next == ChangeType::Modified {
        ChangeType::Modified
    } else if existing != next {
        ChangeType::Modified
    } else {
        existing
    }
}
