//! Show command - print file contents from the forge.

use crate::cli::{parse_repository_ref, ShowCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::workspace::{parse_position, PositionOrLatest};

/// Run the show command.
pub async fn run(cmd: ShowCommand) -> Result<()> {
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

    let response: pb::PathResponse = call(
        &client,
        "/hif.v1.ContentService/GetPath",
        &pb::GetPathRequest {
            repository: Some(repository_ref(org, repository)),
            revision_hash: position.unwrap_or_default(),
            path: cmd.path.trim_start_matches('/').to_string(),
        },
    )
    .await?;

    print!("{}", String::from_utf8_lossy(&response.content));
    Ok(())
}
