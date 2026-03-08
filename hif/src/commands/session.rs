//! Session management commands.

use crate::cli::{looks_like_project_ref, parse_project_ref, SessionCommand, SessionSubcommand};
use crate::config::{self, Config};
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref, user_id_from_token};
use crate::grpc::{Endpoint, GrpcClient};
use crate::workspace::manifest::Manifest;
use crate::workspace::session::{Conversation, Session, SessionState};
use crate::workspace::{collect_changes, ChangeType, WorkspaceManifest};
use std::fs;

/// Run the session command.
pub async fn run(cmd: SessionCommand) -> Result<()> {
    match cmd.command {
        SessionSubcommand::Start { first, second } => {
            let (org, project, goal) = parse_start_args(&first, second.as_deref())?;
            start(&org, &project, &goal).await
        }
        SessionSubcommand::Status => status().await,
        SessionSubcommand::Note { message, role } => note(&role, &message),
        SessionSubcommand::Land => land().await,
        SessionSubcommand::Abandon => abandon().await,
        SessionSubcommand::Resolve { strategy } => resolve(&strategy),
    }
}

/// Parse session start arguments.
///
/// Supports two forms:
/// - In workspace: `hif session start "goal"` - project inferred from workspace
/// - Outside workspace: `hif session start org/project "goal"` - project explicit
fn parse_start_args(first: &str, second: Option<&str>) -> Result<(String, String, String)> {
    match second {
        Some(goal) => {
            let (org, project) = parse_project_ref(first).ok_or_else(|| {
                MicError::InvalidProjectRef(format!(
                    "Invalid project reference '{}'. Use format: org/project",
                    first
                ))
            })?;
            Ok((org.to_string(), project.to_string(), goal.to_string()))
        }
        None => {
            if looks_like_project_ref(first) {
                return Err(MicError::Other(
                    "Missing goal. Usage: hif session start <org/project> \"<goal>\"".to_string(),
                ));
            }

            let manifest = Manifest::find_and_load().map_err(|_| {
                MicError::NotInWorkspace(
                    "Not in a workspace. Either:\n  \
                     1. Run from inside a workspace (created with 'hif checkout'), or\n  \
                     2. Specify the project: hif session start <org/project> \"<goal>\""
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
    if Session::exists()? {
        return Err(MicError::SessionAlreadyActive);
    }

    let mut config = Config::load()?;
    let tokens = config::require_tokens()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let session_id = generate_session_id();
    let user_id = user_id_from_token(&tokens.access_token);
    let repo = repository_ref(organization, project);

    let _session_info: pb::SessionInfo = call(
        &client,
        &tokens.access_token,
        "/hif.v1.VersioningService/OpenSession",
        &pb::SessionOpenRequest {
            user_id,
            repository: Some(repo),
            open: Some(pb::SessionOpen {
                session_id: session_id.clone(),
                goal: goal.to_string(),
                base_position: None,
                requested_workspace: String::new(),
            }),
        },
    )
    .await?;

    let state = Session::start_with_id(organization, project, goal, &session_id)?;

    println!("Session started: {}", state.id);
    println!("Goal: {}", goal);
    println!("Project: {}/{}", organization, project);
    println!();
    println!("Make your changes, then run 'hif session land' to push to the forge.");

    Ok(())
}

/// Show session status.
async fn status() -> Result<()> {
    let state = Session::load()?;

    match state {
        None => {
            println!("No active session.");
            println!("Start one with: hif session start <organization>/<project> <goal>");
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

            if let Ok(remote) = fetch_remote_session_status(&state).await {
                println!();
                println!("Remote status: {}", remote.status);
                if let Some(conflict) = remote.conflict {
                    println!("Conflict at position @{}", conflict.position);
                    if !conflict.paths.is_empty() {
                        for path in conflict.paths {
                            println!("  - {}", path);
                        }
                    }
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
    let user_id = user_id_from_token(&tokens.access_token);

    upload_conversation(&client, &tokens.access_token, &user_id, &state).await?;
    upload_changes(&client, &tokens.access_token, &user_id, &state.id).await?;

    let decisions = state
        .decisions
        .iter()
        .map(|decision| pb::SessionEvent {
            role: "agent".to_string(),
            kind: "decision".to_string(),
            text: format!("{}\n{}", decision.description, decision.reasoning),
            metadata: Vec::new(),
            at_ms: parse_timestamp_ms(&decision.timestamp),
        })
        .collect::<Vec<_>>();

    let response: pb::SessionInfo = call(
        &client,
        &tokens.access_token,
        "/hif.v1.VersioningService/LandSession",
        &pb::LandSessionRequest {
            user_id,
            session_id: state.id.clone(),
            decision: decisions,
            finalize: true,
            epoch: 0,
            force: false,
        },
    )
    .await?;

    if response.status == "conflict" {
        println!("Error: Conflicts detected with upstream changes.");
        if let Some(conflict) = response.conflict {
            println!();
            println!("Conflict position: @{}", conflict.position);
            if !conflict.reason.is_empty() {
                println!("Reason: {}", conflict.reason);
            }
            if !conflict.paths.is_empty() {
                println!("Conflicting files:");
                for path in conflict.paths {
                    println!("  - {}", path);
                }
            }
        }
        println!();
        println!("To resolve:");
        println!("  1. Run 'hif sync' to fetch latest upstream state");
        println!("  2. Merge your local changes");
        println!("  3. Run 'hif session land' again");
        return Err(MicError::ConflictsDetected);
    }

    let landing_position = response
        .current_position
        .as_ref()
        .map(|position| position.id)
        .unwrap_or(0);

    println!("Session landed successfully!");
    println!("Session ID: {}", response.session_id);
    if landing_position > 0 {
        println!("Landing position: {}", landing_position);
    }

    Session::delete()?;
    Ok(())
}

/// Abandon the current session.
async fn abandon() -> Result<()> {
    let state = match Session::load()? {
        Some(state) => state,
        None => {
            println!("No active session to abandon.");
            return Ok(());
        }
    };

    // Best-effort remote abandon. Local cleanup still succeeds if this fails.
    let remote_result: Result<()> = async {
        let mut config = Config::load()?;
        let tokens = config::require_tokens()?;
        let server = config.resolve_default_grpc_url().await?;
        let endpoint = Endpoint::parse(&server)?;
        let client = GrpcClient::new(endpoint);
        let user_id = user_id_from_token(&tokens.access_token);

        let _response: pb::SessionInfo = call(
            &client,
            &tokens.access_token,
            "/hif.v1.VersioningService/AbandonSession",
            &pb::AbandonSessionRequest {
                user_id,
                session_id: state.id.clone(),
            },
        )
        .await?;

        Ok(())
    }
    .await;

    if let Err(error) = remote_result {
        eprintln!(
            "Warning: remote session abandon failed ({}). Local session will still be removed.",
            error
        );
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

async fn fetch_remote_session_status(state: &SessionState) -> Result<pb::SessionInfo> {
    let mut config = Config::load()?;
    let tokens = config::require_tokens()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);
    let user_id = user_id_from_token(&tokens.access_token);

    call(
        &client,
        &tokens.access_token,
        "/hif.v1.VersioningService/GetSession",
        &pb::SessionRequest {
            user_id,
            session_id: state.id.clone(),
        },
    )
    .await
}

async fn upload_conversation(
    client: &GrpcClient,
    access_token: &str,
    user_id: &str,
    state: &SessionState,
) -> Result<()> {
    for note in &state.conversation {
        let event = session_note_event(note);
        let _response: pb::SessionInfo = call(
            client,
            access_token,
            "/hif.v1.VersioningService/AppendSessionConversation",
            &pb::SessionEventAppendRequest {
                user_id: user_id.to_string(),
                session_id: state.id.clone(),
                event: Some(event),
            },
        )
        .await?;
    }

    Ok(())
}

async fn upload_changes(
    client: &GrpcClient,
    access_token: &str,
    user_id: &str,
    session_id: &str,
) -> Result<()> {
    let manifest = WorkspaceManifest::load()?.ok_or(MicError::NoWorkspace)?;
    let workspace_root = std::env::current_dir()?;
    let changes = collect_changes(&workspace_root, &manifest)?;

    for change in changes {
        let content = match change.change_type {
            ChangeType::Deleted => Vec::new(),
            ChangeType::Added | ChangeType::Modified => fs::read(&change.path)?,
        };
        let operation = to_file_operation(&change.path, change.change_type, content);
        let _response: pb::SessionInfo = call(
            client,
            access_token,
            "/hif.v1.VersioningService/AppendSessionChange",
            &pb::SessionChangeAppendRequest {
                user_id: user_id.to_string(),
                session_id: session_id.to_string(),
                operation: Some(operation),
            },
        )
        .await?;
    }

    Ok(())
}

fn session_note_event(note: &Conversation) -> pb::SessionEvent {
    pb::SessionEvent {
        role: note.role.clone(),
        kind: "note".to_string(),
        text: note.message.clone(),
        metadata: Vec::new(),
        at_ms: parse_timestamp_ms(&note.timestamp),
    }
}

fn to_file_operation(path: &str, change_type: ChangeType, content: Vec<u8>) -> pb::FileOperation {
    let action = match change_type {
        ChangeType::Added => pb::file_operation::Action::Create,
        ChangeType::Modified => pb::file_operation::Action::Update,
        ChangeType::Deleted => pb::file_operation::Action::Delete,
    };

    pb::FileOperation {
        action: action as i32,
        path: path.to_string(),
        content,
        old_path: String::new(),
        content_hash: String::new(),
    }
}

fn parse_timestamp_ms(timestamp: &str) -> u64 {
    timestamp
        .parse::<u64>()
        .map(|seconds| seconds.saturating_mul(1_000))
        .unwrap_or_else(|_| chrono::Utc::now().timestamp_millis().max(0) as u64)
}

/// Generate a random session ID.
fn generate_session_id() -> String {
    use base64::Engine;
    let bytes: [u8; 16] = rand::random();
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}
