//! Blame command - show session attribution for file lines.

use crate::cli::{parse_repository_ref, BlameCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output::{self, CliOutput};
use serde::Serialize;

#[derive(Serialize)]
pub(crate) struct BlameLineOutput {
    line: u32,
    session_id: String,
    text: String,
    path: String,
    actor_handle: String,
    revision_hash: Vec<u8>,
    at_ms: u64,
}

#[derive(Serialize)]
pub(crate) struct BlameOutput {
    repository: String,
    path: String,
    lines: Vec<BlameLineOutput>,
}

impl CliOutput for pb::BlameLine {
    type Model = BlameLineOutput;

    fn into_cli_output(self) -> Self::Model {
        BlameLineOutput {
            line: self.line,
            session_id: self.session_id,
            text: self.text,
            path: self.path,
            actor_handle: self.actor_handle,
            revision_hash: self.revision_hash,
            at_ms: self.at_ms,
        }
    }
}

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
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);
    let repo = repository_ref(org, repository);

    let head: pb::RepositoryHeadResponse = call(
        &client,
        "/hif.v1.VersioningService/GetRepositoryHead",
        &pb::GetRepositoryHeadRequest {
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

    let path = cmd.path.clone();
    let response: pb::BlameResponse = call(
        &client,
        "/hif.v1.ContentService/Blame",
        &pb::BlameRequest {
            repository: Some(repo),
            revision_hash: head_revision_hash,
            path: path.clone(),
        },
    )
    .await?;

    if output::use_json() {
        output::print_ok(
            "blame",
            BlameOutput {
                repository: cmd.repository,
                path,
                lines: response.lines.into_cli_output(),
            },
        )?;
    } else {
        for line in response.lines {
            println!("{:>4} {} | {}", line.line, line.session_id, line.text);
        }
    }

    Ok(())
}
