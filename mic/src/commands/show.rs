//! Show command - print file contents from the forge.

use crate::cli::{parse_project_ref, ShowCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::client::{read_field, read_string, write_length_delimited, write_varint_field};
use crate::grpc::{Endpoint, GrpcClient};
use crate::workspace::{parse_position, PositionOrLatest};

/// Run the show command.
pub async fn run(cmd: ShowCommand) -> Result<()> {
    // Parse project reference
    let (org, project) = parse_project_ref(&cmd.project).ok_or_else(|| {
        MicError::InvalidProjectRef(format!(
            "Invalid project reference '{}'. Use format: org/project",
            cmd.project
        ))
    })?;

    let config = Config::load()?;
    let server = config.get_default_server().ok_or(MicError::NoDefaultServer)?;
    let tokens = config::require_tokens()?;
    let endpoint = Endpoint::parse(server)?;
    let client = GrpcClient::new(endpoint);

    // Parse position if provided
    let position: Option<u64> = if let Some(ref pos_str) = cmd.r#ref {
        match parse_position(pos_str) {
            Some(PositionOrLatest::Position(p)) => Some(p),
            Some(PositionOrLatest::Latest) => None,
            None => return Err(MicError::Other("Invalid position format".to_string())),
        }
    } else {
        None
    };

    // Normalize path (remove leading slashes)
    let path = cmd.path.trim_start_matches('/');

    // Build request
    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, org.as_bytes());
    write_length_delimited(&mut request, 2, project.as_bytes());
    write_length_delimited(&mut request, 3, path.as_bytes());
    if let Some(pos) = position {
        write_varint_field(&mut request, 4, pos);
    }

    let response = client
        .unary_call(
            "/micelio.content.v1.ContentService/ReadFile",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    // Parse response
    let content = parse_content_response(&response);
    print!("{}", content);

    Ok(())
}

/// Parse content response.
fn parse_content_response(data: &[u8]) -> String {
    let mut pos = 0;

    while pos < data.len() {
        if let Some((field_number, _, field_data)) = read_field(data, &mut pos) {
            if field_number == 1 {
                return read_string(field_data);
            }
        }
    }

    String::new()
}
