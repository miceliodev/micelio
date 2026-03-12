//! Blame command - show session attribution for file lines.

use crate::cli::{parse_repository_ref, BlameCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output::{self, CliOutput};
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
pub(crate) struct BlameLineOutput {
    line: u32,
    session_id: String,
    text: String,
    path: String,
    attributed_to: IdentityOutput,
    revision_hash: Vec<u8>,
    landed_at: u64,
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
            attributed_to: self.attributed_to.map(identity_output).unwrap_or_default(),
            revision_hash: self.revision_hash,
            landed_at: self.landed_at,
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
    fn ui_snapshot_blame_requires_auth() {
        assert_output_snapshot(
            &["blame", "acme/repo", "README.md"],
            1,
            "",
            "error: Not authenticated. Run 'hif auth login' first.\n",
        );
    }
}
