//! Blame command - show session attribution for file lines.

use crate::cli::{parse_repository_ref, BlameCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref, user_id_from_token};
use crate::grpc::{Endpoint, GrpcClient};

/// Run the blame command.
pub async fn run(cmd: BlameCommand) -> Result<()> {
    let (org, repository) = parse_repository_ref(&cmd.repository).ok_or_else(|| {
        MicError::InvalidRepositoryRef(format!(
            "Invalid repository reference '{}'. Use format: account/repository",
            cmd.repository
        ))
    })?;

    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);
    let user_id = user_id_from_token(&tokens.access_token);
    let repo = repository_ref(org, repository);

    let head: pb::RepositoryHeadResponse = call(
        &client,
        &tokens.access_token,
        "/hif.v1.VersioningService/GetRepositoryHead",
        &pb::GetRepositoryHeadRequest {
            user_id: user_id.clone(),
            repository: Some(repo.clone()),
        },
    )
    .await?;

    let head_revision_hash = head.head.map(|position| position.hash).unwrap_or_default();
    if head_revision_hash.is_empty() {
        return Err(MicError::Other(
            "Failed to resolve repository head revision".to_string(),
        ));
    }

    let response: pb::BlameResponse = call(
        &client,
        &tokens.access_token,
        "/hif.v1.ContentService/Blame",
        &pb::BlameRequest {
            user_id,
            repository: Some(repo),
            revision_hash: head_revision_hash,
            path: cmd.path,
        },
    )
    .await?;

    for line in response.lines {
        println!("{:>4} {} | {}", line.line, line.session_id, line.text);
    }

    Ok(())
}
