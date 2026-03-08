//! Log command - list landed sessions.

use crate::cli::{parse_project_ref, LogCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref, user_id_from_token};
use crate::grpc::{Endpoint, GrpcClient};

/// Run the log command.
pub async fn run(cmd: LogCommand) -> Result<()> {
    // Parse repository reference
    let (org, repository) = parse_project_ref(&cmd.project).ok_or_else(|| {
        MicError::InvalidProjectRef(format!(
            "Invalid repository reference '{}'. Use format: org/project",
            cmd.project
        ))
    })?;

    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);
    let user_id = user_id_from_token(&tokens.access_token);

    let response: pb::ListSessionsResponse = call(
        &client,
        &tokens.access_token,
        "/hif.v1.VersioningService/ListSessions",
        &pb::ListSessionsRequest {
            user_id,
            repository: Some(repository_ref(org, repository)),
            path: cmd.path.clone().unwrap_or_default(),
            limit: cmd.limit,
        },
    )
    .await?;

    for session in response.sessions {
        println!("@{} {}", session.position, session.id);
        println!("  Goal: {}", session.goal);
        println!("  Author: {}", session.author);
        println!();
    }

    Ok(())
}
