//! Diff command - show changes between two positions.

use crate::cli::{parse_project_ref, DiffCommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::client::{read_field, read_string, write_length_delimited, write_varint_field};
use crate::grpc::{Endpoint, GrpcClient};
use crate::workspace::{parse_position, PositionOrLatest};
use colored::Colorize;

/// Run the diff command.
pub async fn run(cmd: DiffCommand) -> Result<()> {
    // Parse project reference
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

    // Parse positions
    let from_position: Option<u64> = match parse_position(&cmd.from) {
        Some(PositionOrLatest::Position(p)) => Some(p),
        Some(PositionOrLatest::Latest) => None,
        None => return Err(MicError::Other("Invalid from position".to_string())),
    };

    let to_position: Option<u64> = if let Some(ref to) = cmd.to {
        match parse_position(to) {
            Some(PositionOrLatest::Position(p)) => Some(p),
            Some(PositionOrLatest::Latest) => None,
            None => return Err(MicError::Other("Invalid to position".to_string())),
        }
    } else {
        None
    };

    // Build request
    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, org.as_bytes());
    write_length_delimited(&mut request, 2, project.as_bytes());
    if let Some(pos) = from_position {
        write_varint_field(&mut request, 3, pos);
    }
    if let Some(pos) = to_position {
        write_varint_field(&mut request, 4, pos);
    }

    let response = client
        .unary_call(
            "/micelio.content.v1.ContentService/DiffTree",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    // Parse response
    let diffs = parse_diff_response(&response);

    for diff in diffs {
        match diff.change_type.as_str() {
            "added" => println!("{} {}", "A".green(), diff.path.green()),
            "deleted" => println!("{} {}", "D".red(), diff.path.red()),
            "modified" => println!("{} {}", "M".yellow(), diff.path.yellow()),
            _ => println!("? {}", diff.path),
        }
    }

    Ok(())
}

/// Diff entry.
struct DiffEntry {
    path: String,
    change_type: String,
}

/// Parse diff response.
fn parse_diff_response(data: &[u8]) -> Vec<DiffEntry> {
    let mut diffs = Vec::new();
    let mut pos = 0;

    while pos < data.len() {
        if let Some((field_number, _, field_data)) = read_field(data, &mut pos) {
            if field_number == 1 {
                let diff = parse_diff_entry(field_data);
                diffs.push(diff);
            }
        }
    }

    diffs
}

/// Parse diff entry.
fn parse_diff_entry(data: &[u8]) -> DiffEntry {
    let mut pos = 0;
    let mut path = String::new();
    let mut change_type = String::new();

    while pos < data.len() {
        if let Some((field_number, _, field_data)) = read_field(data, &mut pos) {
            match field_number {
                1 => path = read_string(field_data),
                2 => change_type = read_string(field_data),
                _ => {}
            }
        }
    }

    DiffEntry { path, change_type }
}
