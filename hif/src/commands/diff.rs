//! Diff command - show changes between two revisions.

use crate::cli::{parse_repository_ref, DiffCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;
use crate::workspace::{parse_position, PositionOrLatest};
use colored::Colorize;
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Serialize)]
pub(crate) struct DiffChangeOutput {
    path: String,
    change_type: String,
}

#[derive(Serialize)]
pub(crate) struct DiffOutput {
    repository: String,
    from: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    to: Option<String>,
    changes: Vec<DiffChangeOutput>,
}

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
    if output::use_json() {
        let items = changes
            .iter()
            .map(|(path, change_type)| {
                let change_type = match change_type {
                    ChangeType::Added => "added",
                    ChangeType::Deleted => "deleted",
                    ChangeType::Modified => "modified",
                };

                DiffChangeOutput {
                    path: path.clone(),
                    change_type: change_type.to_string(),
                }
            })
            .collect::<Vec<_>>();

        output::print_ok(
            "diff",
            DiffOutput {
                repository: cmd.repository,
                from: cmd.from,
                to: cmd.to,
                changes: items,
            },
        )?;
    } else {
        for (path, change_type) in changes {
            match change_type {
                ChangeType::Added => output::ui_line(format!("{} {}", "A".green(), path.green())),
                ChangeType::Deleted => output::ui_line(format!("{} {}", "D".red(), path.red())),
                ChangeType::Modified => {
                    output::ui_line(format!("{} {}", "M".yellow(), path.yellow()))
                }
            }
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

#[cfg(test)]
mod tests {
    use crate::commands::ui_test_support::assert_output_snapshot;

    #[test]
    fn ui_snapshot_diff_invalid_from_revision() {
        assert_output_snapshot(
            &["diff", "acme/repo", "aaaaa"],
            1,
            "",
            "error: Invalid FROM revision\n",
        );
    }
}
