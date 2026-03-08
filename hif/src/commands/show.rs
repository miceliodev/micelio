//! Show command - print file contents from the forge.

use crate::cli::{parse_project_ref, ShowCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref, user_id_from_token};
use crate::grpc::{Endpoint, GrpcClient};
use crate::workspace::{parse_position, PositionOrLatest};

/// Run the show command.
pub async fn run(cmd: ShowCommand) -> Result<()> {
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

    let response: pb::PathResponse = call(
        &client,
        &tokens.access_token,
        "/hif.v1.ContentService/GetPath",
        &pb::GetPathRequest {
            user_id,
            repository: Some(repository_ref(org, project)),
            revision_hash: position.unwrap_or_default(),
            path: cmd.path.trim_start_matches('/').to_string(),
        },
    )
    .await?;

    print!("{}", String::from_utf8_lossy(&response.content));
    Ok(())
}
