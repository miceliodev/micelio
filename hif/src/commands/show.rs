//! Show command - print file contents from the forge.

use crate::cli::{parse_repository_ref, ShowCommand};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;
use crate::workspace::{parse_position, PositionOrLatest};
use serde::Serialize;

#[derive(Serialize)]
pub(crate) struct ShowOutput {
    repository: String,
    path: String,
    content: String,
    encoding: String,
    content_hash: Vec<u8>,
    size: u64,
    mode: u32,
}

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

    if output::use_json() {
        use base64::Engine;

        let (content, encoding) = match String::from_utf8(response.content.clone()) {
            Ok(text) => (text, "utf8"),
            Err(_) => (
                base64::engine::general_purpose::STANDARD.encode(&response.content),
                "base64",
            ),
        };

        output::print_ok(
            "show",
            ShowOutput {
                repository: cmd.repository,
                path: cmd.path.trim_start_matches('/').to_string(),
                content,
                encoding: encoding.to_string(),
                content_hash: response.content_hash,
                size: response.size,
                mode: response.mode,
            },
        )?;
    } else {
        print!("{}", String::from_utf8_lossy(&response.content));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use crate::commands::ui_test_support::assert_output_snapshot;

    #[test]
    fn ui_snapshot_show_requires_auth() {
        assert_output_snapshot(
            &["show", "acme/repo", "README.md"],
            1,
            "",
            "error: Not authenticated. Run 'hif auth login' first.\n",
        );
    }
}
