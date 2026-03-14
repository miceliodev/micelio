//! Log command - list landed sessions.

use crate::cli::{parse_repository_ref, LogCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;
use serde::Serialize;

#[derive(Serialize, Default)]
pub(crate) struct IdentityOutput {
    id: String,
    acct: String,
    handle: String,
    instance: String,
    kind: String,
}

#[derive(Serialize)]
pub(crate) struct LogSessionOutput {
    id: String,
    goal: String,
    attributed_to: IdentityOutput,
    revision: String,
}

#[derive(Serialize)]
pub(crate) struct LogOutput {
    repository: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    path: Option<String>,
    limit: u32,
    sessions: Vec<LogSessionOutput>,
}

/// Run the log command.
pub async fn run(cmd: LogCommand) -> Result<()> {
    // Parse repository reference
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

    let response: pb::ListSessionsResponse = call(
        &client,
        "/hif.v1.VersioningService/ListSessions",
        &pb::ListSessionsRequest {
            repository: Some(repository_ref(org, repository)),
            path: cmd.path.clone().unwrap_or_default(),
            limit: cmd.limit,
        },
    )
    .await?;

    let sessions = response
        .sessions
        .into_iter()
        .map(|session| {
            let revision = if session.revision_hash.is_empty() {
                "0000000000000000000000000000000000000000000000000000000000000000".to_string()
            } else {
                session
                    .revision_hash
                    .iter()
                    .map(|byte| format!("{:02x}", byte))
                    .collect::<String>()
            };

            LogSessionOutput {
                id: session.id,
                goal: session.goal,
                attributed_to: session
                    .attributed_to
                    .map(identity_output)
                    .unwrap_or_default(),
                revision,
            }
        })
        .collect::<Vec<_>>();

    if output::use_json() {
        output::print_ok(
            "log",
            LogOutput {
                repository: cmd.repository,
                path: cmd.path,
                limit: cmd.limit,
                sessions,
            },
        )?;
    } else {
        for session in sessions {
            output::ui_line(format!("{} {}", session.revision, session.id));
            output::ui_line(format!("  goal: {}", session.goal));
            output::ui_line(format!(
                "  attributed-to: {}",
                display_identity(&session.attributed_to)
            ));
            output::ui_blank_line();
        }
    }

    Ok(())
}

fn display_identity(identity: &IdentityOutput) -> String {
    if !identity.handle.is_empty() {
        identity.handle.clone()
    } else if !identity.acct.is_empty() {
        identity.acct.clone()
    } else if !identity.id.is_empty() {
        identity.id.clone()
    } else {
        "unknown".to_string()
    }
}

fn identity_output(identity: pb::IdentityRef) -> IdentityOutput {
    IdentityOutput {
        id: identity.id,
        acct: identity.acct,
        handle: identity.handle,
        instance: identity.instance,
        kind: identity.kind,
    }
}

#[cfg(test)]
mod tests {
    use crate::commands::ui_test_support::assert_output_snapshot;

    #[test]
    fn ui_snapshot_log_requires_auth() {
        assert_output_snapshot(
            &["log", "acme/repo"],
            1,
            "",
            "error: Not authenticated. Run 'hif auth login' first.\n",
        );
    }
}
