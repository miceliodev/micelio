//! Log command - list landed sessions.

use crate::cli::{parse_repository_ref, LogCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;

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

            serde_json::json!({
                "id": session.id,
                "goal": session.goal,
                "author": session.author,
                "revision": revision
            })
        })
        .collect::<Vec<_>>();

    if output::use_json() {
        output::print_ok(
            "log",
            serde_json::json!({
                "repository": cmd.repository,
                "path": cmd.path,
                "limit": cmd.limit,
                "sessions": sessions
            }),
        )?;
    } else {
        for session in &sessions {
            println!(
                "{} {}",
                session["revision"].as_str().unwrap_or_default(),
                session["id"].as_str().unwrap_or_default()
            );
            println!("  Goal: {}", session["goal"].as_str().unwrap_or_default());
            println!(
                "  Author: {}",
                session["author"].as_str().unwrap_or_default()
            );
            println!();
        }
    }

    Ok(())
}
