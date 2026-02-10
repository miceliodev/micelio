//! Blame command - show session attribution for file lines.

use crate::cli::{parse_project_ref, BlameCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::client::{read_field, read_string, write_length_delimited};
use crate::grpc::{Endpoint, GrpcClient};

/// Run the blame command.
pub async fn run(cmd: BlameCommand) -> Result<()> {
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

    // Build request
    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, org.as_bytes());
    write_length_delimited(&mut request, 2, project.as_bytes());
    write_length_delimited(&mut request, 3, cmd.path.as_bytes());

    let response = client
        .unary_call(
            "/micelio.content.v1.ContentService/BlameFile",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    // Parse response
    let lines = parse_blame_response(&response);
    for (line_num, line) in lines.iter().enumerate() {
        println!("{:>4} {} | {}", line_num + 1, line.session_id, line.content);
    }

    Ok(())
}

/// Blame line.
struct BlameLine {
    session_id: String,
    content: String,
}

/// Parse blame response.
fn parse_blame_response(data: &[u8]) -> Vec<BlameLine> {
    let mut lines = Vec::new();
    let mut pos = 0;

    while pos < data.len() {
        if let Some((field_number, _, field_data)) = read_field(data, &mut pos) {
            if field_number == 1 {
                let line = parse_blame_line(field_data);
                lines.push(line);
            }
        }
    }

    lines
}

/// Parse blame line.
fn parse_blame_line(data: &[u8]) -> BlameLine {
    let mut pos = 0;
    let mut session_id = String::new();
    let mut content = String::new();

    while pos < data.len() {
        if let Some((field_number, _, field_data)) = read_field(data, &mut pos) {
            match field_number {
                1 => session_id = read_string(field_data),
                2 => content = read_string(field_data),
                _ => {}
            }
        }
    }

    BlameLine { session_id, content }
}
