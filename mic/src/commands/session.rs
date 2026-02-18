//! Session management commands.

use crate::cli::{looks_like_project_ref, parse_project_ref, SessionCommand, SessionSubcommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::client::{read_field, read_string, read_varint_value, write_length_delimited};
use crate::grpc::{Endpoint, GrpcClient};
use crate::workspace::manifest::Manifest;
use crate::workspace::session::Session;

/// Run the session command.
pub async fn run(cmd: SessionCommand) -> Result<()> {
    match cmd.command {
        SessionSubcommand::Start { first, second } => {
            let (org, project, goal) = parse_start_args(&first, second.as_deref())?;
            start(&org, &project, &goal).await
        }
        SessionSubcommand::Status => status(),
        SessionSubcommand::Note { message, role } => note(&role, &message),
        SessionSubcommand::Land => land().await,
        SessionSubcommand::Abandon => abandon(),
        SessionSubcommand::Resolve { strategy } => resolve(&strategy),
    }
}

/// Parse session start arguments.
///
/// Supports two forms:
/// - In workspace: `mic session start "goal"` - project inferred from workspace
/// - Outside workspace: `mic session start org/project "goal"` - project explicit
fn parse_start_args(first: &str, second: Option<&str>) -> Result<(String, String, String)> {
    match second {
        // Two args: first is org/project, second is goal
        Some(goal) => {
            let (org, project) = parse_project_ref(first).ok_or_else(|| {
                MicError::InvalidProjectRef(format!(
                    "Invalid project reference '{}'. Use format: org/project",
                    first
                ))
            })?;
            Ok((org.to_string(), project.to_string(), goal.to_string()))
        }
        // One arg: could be just goal (in workspace) or error
        None => {
            // Check if first arg looks like a project reference
            if looks_like_project_ref(first) {
                return Err(MicError::Other(
                    "Missing goal. Usage: mic session start <org/project> \"<goal>\"".to_string(),
                ));
            }

            // Try to infer project from workspace
            let manifest = Manifest::find_and_load().map_err(|_| {
                MicError::NotInWorkspace(
                    "Not in a workspace. Either:\n  \
                     1. Run from inside a workspace (created with 'mic checkout'), or\n  \
                     2. Specify the project: mic session start <org/project> \"<goal>\""
                        .to_string(),
                )
            })?;

            Ok((
                manifest.organization.clone(),
                manifest.project.clone(),
                first.to_string(),
            ))
        }
    }
}

/// Start a new session.
async fn start(organization: &str, project: &str, goal: &str) -> Result<()> {
    // Check if a session is already active
    if Session::exists()? {
        return Err(MicError::SessionAlreadyActive);
    }

    let mut config = Config::load()?;
    let tokens = config::require_tokens()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    // Generate session ID
    let session_id = generate_session_id();

    // Start session on server
    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, organization.as_bytes());
    write_length_delimited(&mut request, 2, project.as_bytes());
    write_length_delimited(&mut request, 3, session_id.as_bytes());
    write_length_delimited(&mut request, 4, goal.as_bytes());

    let _ = client
        .unary_call(
            "/micelio.sessions.v1.SessionService/StartSession",
            &request,
            Some(&tokens.access_token),
        )
        .await?;

    // Create local session
    let state = Session::start(organization, project, goal)?;

    println!("Session started: {}", state.id);
    println!("Goal: {}", goal);
    println!("Project: {}/{}", organization, project);
    println!();
    println!("Make your changes, then run 'mic session land' to push to the forge.");

    Ok(())
}

/// Show session status.
fn status() -> Result<()> {
    let state = Session::load()?;

    match state {
        None => {
            println!("No active session.");
            println!("Start one with: mic session start <organization> <project> <goal>");
        }
        Some(state) => {
            println!("Active session: {}", state.id);
            println!("Goal: {}", state.goal);
            println!("Project: {}/{}", state.project_org, state.project_handle);
            println!("Started: {}", state.started_at);

            if !state.conversation.is_empty() {
                println!();
                println!("Conversation ({} messages):", state.conversation.len());
                for msg in &state.conversation {
                    println!("  [{}] {}", msg.role, msg.message);
                }
            }

            if !state.decisions.is_empty() {
                println!();
                println!("Decisions ({}):", state.decisions.len());
                for decision in &state.decisions {
                    println!("  - {}", decision.description);
                    println!("    Reasoning: {}", decision.reasoning);
                }
            }

            if !state.files.is_empty() {
                println!();
                println!("Files ({}):", state.files.len());
                for file in &state.files {
                    println!("  {} ({})", file.path, file.change_type);
                }
            }
        }
    }

    Ok(())
}

/// Add a note to the session.
fn note(role: &str, message: &str) -> Result<()> {
    Session::add_note(role, message)?;
    println!("Note added to session.");
    Ok(())
}

/// Land the current session.
async fn land() -> Result<()> {
    let state = Session::load()?.ok_or(MicError::NoActiveSession)?;
    let mut config = Config::load()?;
    let tokens = config::require_tokens()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    // Get files from overlay
    let files = Session::get_overlay_files()?;

    // Encode land request
    let mut request = Vec::new();
    write_length_delimited(&mut request, 1, state.id.as_bytes());

    // Add file changes
    for file in &files {
        let mut change = Vec::new();
        write_length_delimited(&mut change, 1, file.path.as_bytes());
        write_length_delimited(&mut change, 2, file.content.as_bytes());
        write_length_delimited(&mut change, 3, file.change_type.as_bytes());
        write_length_delimited(&mut request, 2, &change);
    }

    let result = client
        .unary_call_result(
            "/micelio.sessions.v1.SessionService/LandSession",
            &request,
            Some(&tokens.access_token),
        )
        .await;

    match result {
        crate::grpc::client::GrpcResult::Ok(response) => {
            // Parse response
            let (session_id, landing_position) = parse_land_response(&response);

            println!("Session landed successfully!");
            println!("Session ID: {}", session_id);
            if landing_position > 0 {
                println!("Landing position: {}", landing_position);
            }

            // Clean up local session
            Session::delete()?;

            Ok(())
        }
        crate::grpc::client::GrpcResult::Err(message) => {
            // Check for conflict error
            if message.starts_with("Conflicts detected: ") {
                let paths = message
                    .strip_prefix("Conflicts detected: ")
                    .unwrap_or("")
                    .split(", ")
                    .collect::<Vec<_>>();

                println!("Error: Conflicts detected with upstream changes.");
                println!();
                println!("Conflicting files:");
                for path in paths {
                    println!("  - {}", path);
                }
                println!();
                println!("To resolve:");
                println!("  1. Run 'mic sync' to fetch the latest upstream state");
                println!("  2. Review and merge your changes with the upstream versions");
                println!("  3. Run 'mic session land' again");

                Err(MicError::ConflictsDetected)
            } else {
                Err(MicError::LandingFailed(message))
            }
        }
    }
}

/// Abandon the current session.
fn abandon() -> Result<()> {
    if !Session::exists()? {
        println!("No active session to abandon.");
        return Ok(());
    }

    Session::delete()?;
    println!("Session abandoned.");
    Ok(())
}

/// Resolve conflicts.
fn resolve(strategy: &str) -> Result<()> {
    println!("Conflict resolution is not yet implemented.");
    println!("Available strategies: ours, theirs, interactive");
    println!("Strategy: {}", strategy);
    Ok(())
}

/// Generate a random session ID.
fn generate_session_id() -> String {
    use base64::Engine;
    let bytes: [u8; 16] = rand::random();
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

/// Parse land response.
fn parse_land_response(data: &[u8]) -> (String, u64) {
    let mut pos = 0;
    let mut session_id = String::new();
    let mut landing_position = 0u64;

    while pos < data.len() {
        if let Some((field_number, _, field_data)) = read_field(data, &mut pos) {
            match field_number {
                1 => session_id = read_string(field_data),
                2 => landing_position = read_varint_value(field_data),
                _ => {}
            }
        }
    }

    (session_id, landing_position)
}
