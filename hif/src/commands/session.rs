//! Session management commands.

use crate::cli::{
    looks_like_repository_ref, parse_repository_ref, SessionCommand, SessionSubcommand,
};
use crate::config::Config;
use crate::error::{MicError, Result};
use crate::grpc::hif_v1::{call, pb, repository_ref};
use crate::grpc::{Endpoint, GrpcClient};
use crate::output;
use crate::workspace::manifest::Manifest;
use crate::workspace::session::{Conversation, Decision, FileChange, Session, SessionState};
use crate::workspace::{collect_changes, ChangeType, WorkspaceManifest};
use serde::Serialize;
use std::fs;

#[derive(Serialize)]
pub(crate) struct SessionStartOutput {
    session_id: String,
    goal: String,
    account: String,
    repository: String,
}

#[derive(Serialize)]
pub(crate) struct SessionStatusOutput {
    active: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    goal: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    account: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    repository: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    started_at: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    conversation: Vec<Conversation>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    decisions: Vec<Decision>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    files: Vec<FileChange>,
    #[serde(skip_serializing_if = "Option::is_none")]
    remote: Option<RemoteSessionStatusOutput>,
}

#[derive(Serialize)]
pub(crate) struct SessionNoteOutput {
    role: String,
    message: String,
}

#[derive(Serialize)]
pub(crate) struct SessionLandOutput {
    session_id: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    revision: String,
}

#[derive(Serialize)]
pub(crate) struct SessionAbandonOutput {
    abandoned: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    session_id: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct SessionResolveOutput {
    implemented: bool,
    strategy: String,
}

#[derive(Serialize)]
pub(crate) struct SessionRepositoryOutput {
    account: String,
    repository: String,
}

#[derive(Serialize)]
pub(crate) struct SessionPositionOutput {
    hash: String,
    at: String,
}

#[derive(Serialize)]
pub(crate) struct SessionConflictOutput {
    revision_hash: String,
    session_id: String,
    reason: String,
    paths: Vec<String>,
}

#[derive(Serialize)]
pub(crate) struct RemoteSessionStatusOutput {
    session_id: String,
    goal: String,
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    repository: Option<SessionRepositoryOutput>,
    #[serde(skip_serializing_if = "Option::is_none")]
    base_position: Option<SessionPositionOutput>,
    #[serde(skip_serializing_if = "Option::is_none")]
    current_position: Option<SessionPositionOutput>,
    conversation_count: usize,
    decisions_count: usize,
    changes_count: usize,
    created_at_ms: u64,
    updated_at_ms: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    conflict: Option<SessionConflictOutput>,
}

/// Run the session command.
pub async fn run(cmd: SessionCommand) -> Result<()> {
    match cmd.command {
        SessionSubcommand::Start { first, second } => {
            let (org, repository, goal) = parse_start_args(&first, second.as_deref())?;
            start(&org, &repository, &goal).await
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
/// - In workspace: `hif session start "goal"` - repository inferred from workspace
/// - Outside workspace: `hif session start account/repository "goal"` - repository explicit
fn parse_start_args(first: &str, second: Option<&str>) -> Result<(String, String, String)> {
    match second {
        Some(goal) => {
            let (org, repository) = parse_repository_ref(first).ok_or_else(|| {
                MicError::InvalidRepositoryRef(format!(
                    "Invalid repository reference '{}'. Use format: account/repository",
                    first
                ))
            })?;
            Ok((org.to_string(), repository.to_string(), goal.to_string()))
        }
        None => {
            if looks_like_repository_ref(first) {
                return Err(MicError::Other(
                    "Missing goal. Usage: hif session start <account/repository> \"<goal>\""
                        .to_string(),
                ));
            }

            let manifest = Manifest::find_and_load().map_err(|_| {
                MicError::NotInWorkspace(
                    "Not in a workspace. Either:\n  \
                     1. Run from inside a workspace (created with 'hif checkout'), or\n  \
                     2. Specify the repository: hif session start <account/repository> \"<goal>\""
                        .to_string(),
                )
            })?;

            Ok((
                manifest.organization.clone(),
                manifest.repository.clone(),
                first.to_string(),
            ))
        }
    }
}

/// Start a new session.
async fn start(organization: &str, repository: &str, goal: &str) -> Result<()> {
    if Session::exists()? {
        return Err(MicError::SessionAlreadyActive);
    }

    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    let session_id = generate_session_id();
    let repo = repository_ref(organization, repository);

    let _session_info: pb::SessionInfo = call(
        &client,
        "/hif.v1.VersioningService/OpenSession",
        &pb::SessionOpenRequest {
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

    let state = Session::start_with_id(organization, repository, goal, &session_id)?;

    if output::use_json() {
        output::print_ok(
            "session.start",
            SessionStartOutput {
                session_id: state.id,
                goal: goal.to_string(),
                account: organization.to_string(),
                repository: repository.to_string(),
            },
        )?;
    } else {
        output::set_success_message(format!(
            "Started session {} for '{}/{}'.",
            state.id, organization, repository
        ));
        output::add_next_step("hif session land");
    }

    Ok(())
}

/// Show session status.
async fn status() -> Result<()> {
    let state = Session::load()?;
    let json_output = output::use_json();

    match state {
        None => {
            if json_output {
                output::print_ok(
                    "session.status",
                    SessionStatusOutput {
                        active: false,
                        session_id: None,
                        goal: None,
                        account: None,
                        repository: None,
                        started_at: None,
                        conversation: Vec::new(),
                        decisions: Vec::new(),
                        files: Vec::new(),
                        remote: None,
                    },
                )?;
            } else {
                println!("no active session");
                println!("start one with: hif session start <account>/<repository> <goal>");
            }
        }
        Some(state) => {
            let remote = fetch_remote_session_status(&state).await.ok();
            if json_output {
                output::print_ok(
                    "session.status",
                    SessionStatusOutput {
                        active: true,
                        session_id: Some(state.id.clone()),
                        goal: Some(state.goal.clone()),
                        account: Some(state.repository_org.clone()),
                        repository: Some(state.repository_handle.clone()),
                        started_at: Some(state.started_at.clone()),
                        conversation: state.conversation.clone(),
                        decisions: state.decisions.clone(),
                        files: state.files.clone(),
                        remote: remote.as_ref().map(session_info_output),
                    },
                )?;
            } else {
                println!("Session {}", state.id);
                println!("Goal {}", state.goal);
                println!(
                    "Repository {}/{}",
                    state.repository_org, state.repository_handle
                );
                println!("Started {}", state.started_at);

                if !state.conversation.is_empty() {
                    println!();
                    println!("conversation ({}):", state.conversation.len());
                    for msg in &state.conversation {
                        println!("  [{}] {}", msg.role, msg.message);
                    }
                }

                if !state.decisions.is_empty() {
                    println!();
                    println!("decisions ({}):", state.decisions.len());
                    for decision in &state.decisions {
                        println!("  - {}", decision.description);
                        println!("    reasoning: {}", decision.reasoning);
                    }
                }

                if !state.files.is_empty() {
                    println!();
                    println!("files ({}):", state.files.len());
                    for file in &state.files {
                        println!("  {} ({})", file.path, file.change_type);
                    }
                }

                if let Some(remote) = remote.as_ref() {
                    println!();
                    println!("remote-status {}", remote.status);
                    if let Some(conflict) = remote.conflict.as_ref() {
                        println!(
                            "conflict-revision {}",
                            format_revision_hash(&conflict.revision_hash)
                        );
                        if !conflict.paths.is_empty() {
                            for path in &conflict.paths {
                                println!("  - {}", path);
                            }
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
    if output::use_json() {
        output::print_ok(
            "session.note",
            SessionNoteOutput {
                role: role.to_string(),
                message: message.to_string(),
            },
        )?;
    } else {
        output::set_success_message("Added note to session.");
    }
    Ok(())
}

/// Land the current session.
async fn land() -> Result<()> {
    let state = Session::load()?.ok_or(MicError::NoActiveSession)?;
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    upload_conversation(&client, &state).await?;
    upload_changes(&client, &state.id).await?;

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
        "/hif.v1.VersioningService/LandSession",
        &pb::LandSessionRequest {
            session_id: state.id.clone(),
            decision: decisions,
            finalize: true,
            epoch: 0,
            force: false,
        },
    )
    .await?;

    if response.status == "conflict" {
        if output::use_json() {
            let details = response.conflict.as_ref().map(session_conflict_output);
            return Err(MicError::Other(format!(
                "Conflicts detected with upstream changes: {}",
                serde_json::to_string(&details).unwrap_or_else(|_| "null".to_string())
            )));
        }

        output::warn("Conflicts detected with upstream changes.");
        if let Some(conflict) = response.conflict.as_ref() {
            output::warn(format!(
                "Conflict revision: {}.",
                format_revision_hash(&conflict.revision_hash)
            ));
            if !conflict.reason.is_empty() {
                output::warn(format!("Reason: {}.", conflict.reason));
            }
            if !conflict.paths.is_empty() {
                output::warn("Conflicting files:");
                for path in &conflict.paths {
                    output::warn(format!("- {}", path));
                }
            }
        }
        output::add_next_step("hif sync");
        output::add_next_step("Merge local changes.");
        output::add_next_step("hif session land");
        return Err(MicError::ConflictsDetected);
    }

    let landing_revision = response
        .current_position
        .as_ref()
        .map(|position| format_revision_hash(&position.hash))
        .unwrap_or_else(|| String::new());

    if output::use_json() {
        output::print_ok(
            "session.land",
            SessionLandOutput {
                session_id: response.session_id,
                revision: landing_revision,
            },
        )?;
    } else {
        let mut message = format!("Landed session {}.", response.session_id);
        if !landing_revision.is_empty() {
            message.push_str(&format!(" Revision {}.", landing_revision));
        }
        output::set_success_message(message);
    }

    Session::delete()?;
    Ok(())
}

/// Abandon the current session.
async fn abandon() -> Result<()> {
    let state = match Session::load()? {
        Some(state) => state,
        None => {
            if output::use_json() {
                output::print_ok(
                    "session.abandon",
                    SessionAbandonOutput {
                        abandoned: false,
                        session_id: None,
                    },
                )?;
            } else {
                output::set_success_message("No active session to abandon.");
            }
            return Ok(());
        }
    };

    // Best-effort remote abandon. Local cleanup still succeeds if this fails.
    let remote_result: Result<()> = async {
        let mut config = Config::load()?;
        let server = config.resolve_default_grpc_url().await?;
        let endpoint = Endpoint::parse(&server)?;
        let client = GrpcClient::new(endpoint);

        let _response: pb::SessionInfo = call(
            &client,
            "/hif.v1.VersioningService/AbandonSession",
            &pb::AbandonSessionRequest {
                session_id: state.id.clone(),
            },
        )
        .await?;

        Ok(())
    }
    .await;

    if let Err(error) = remote_result {
        output::warn(format!(
            "Remote session abandon failed ({}). Local session was still removed.",
            error
        ));
    }

    Session::delete()?;
    if output::use_json() {
        output::print_ok(
            "session.abandon",
            SessionAbandonOutput {
                abandoned: true,
                session_id: Some(state.id),
            },
        )?;
    } else {
        output::set_success_message("Abandoned session.");
    }
    Ok(())
}

/// Resolve conflicts.
fn resolve(strategy: &str) -> Result<()> {
    if output::use_json() {
        output::print_ok(
            "session.resolve",
            SessionResolveOutput {
                implemented: false,
                strategy: strategy.to_string(),
            },
        )?;
    } else {
        output::warn("Conflict resolution is not implemented.");
        output::warn("Available strategies: ours, theirs, interactive.");
        output::set_success_message(format!("Requested strategy: {}.", strategy));
    }
    Ok(())
}

fn session_info_output(info: &pb::SessionInfo) -> RemoteSessionStatusOutput {
    RemoteSessionStatusOutput {
        session_id: info.session_id.clone(),
        goal: info.goal.clone(),
        status: info.status.clone(),
        repository: info
            .repository
            .as_ref()
            .map(|repository| SessionRepositoryOutput {
                account: repository.account_handle.clone(),
                repository: repository.repository_handle.clone(),
            }),
        base_position: info.base_position.as_ref().map(position_output),
        current_position: info.current_position.as_ref().map(position_output),
        conversation_count: info.conversation.len(),
        decisions_count: info.decisions.len(),
        changes_count: info.changes.len(),
        created_at_ms: info.created_at_ms,
        updated_at_ms: info.updated_at_ms,
        conflict: info.conflict.as_ref().map(session_conflict_output),
    }
}

fn session_conflict_output(conflict: &pb::SessionConflict) -> SessionConflictOutput {
    SessionConflictOutput {
        revision_hash: format_revision_hash(&conflict.revision_hash),
        session_id: conflict.session_id.clone(),
        reason: conflict.reason.clone(),
        paths: conflict.paths.clone(),
    }
}

fn position_output(position: &pb::Position) -> SessionPositionOutput {
    SessionPositionOutput {
        hash: format_revision_hash(&position.hash),
        at: position.at.clone(),
    }
}

async fn fetch_remote_session_status(state: &SessionState) -> Result<pb::SessionInfo> {
    let mut config = Config::load()?;
    let server = config.resolve_default_grpc_url().await?;
    let endpoint = Endpoint::parse(&server)?;
    let client = GrpcClient::new(endpoint);

    call(
        &client,
        "/hif.v1.VersioningService/GetSession",
        &pb::SessionRequest {
            session_id: state.id.clone(),
        },
    )
    .await
}

async fn upload_conversation(client: &GrpcClient, state: &SessionState) -> Result<()> {
    for note in &state.conversation {
        let event = session_note_event(note);
        let _response: pb::SessionInfo = call(
            client,
            "/hif.v1.VersioningService/AppendSessionConversation",
            &pb::SessionEventAppendRequest {
                session_id: state.id.clone(),
                event: Some(event),
            },
        )
        .await?;
    }

    Ok(())
}

async fn upload_changes(client: &GrpcClient, session_id: &str) -> Result<()> {
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
            "/hif.v1.VersioningService/AppendSessionChange",
            &pb::SessionChangeAppendRequest {
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

fn format_revision_hash(hash: &[u8]) -> String {
    if hash.is_empty() {
        return "0000000000000000000000000000000000000000000000000000000000000000".to_string();
    }

    hash.iter()
        .map(|byte| format!("{:02x}", byte))
        .collect::<String>()
}

#[cfg(test)]
mod tests {
    use crate::commands::ui_test_support::assert_output_snapshot;

    #[test]
    fn ui_snapshot_session_start_requires_auth() {
        assert_output_snapshot(
            &["session", "start", "acme/repo", "goal"],
            1,
            "",
            "error: Not authenticated. Run 'hif auth login' first.\n",
        );
    }

    #[test]
    fn ui_snapshot_session_status_without_active_session() {
        assert_output_snapshot(
            &["session", "status"],
            0,
            "no active session\nstart one with: hif session start <account>/<repository> <goal>\n",
            "",
        );
    }

    #[test]
    fn ui_snapshot_session_note_without_active_session() {
        assert_output_snapshot(
            &["session", "note", "hello"],
            1,
            "",
            "error: No active session. Start one with 'hif session start'.\n",
        );
    }

    #[test]
    fn ui_snapshot_session_land_without_active_session() {
        assert_output_snapshot(
            &["session", "land"],
            1,
            "",
            "error: No active session. Start one with 'hif session start'.\n",
        );
    }

    #[test]
    fn ui_snapshot_session_abandon_without_active_session() {
        assert_output_snapshot(
            &["session", "abandon"],
            0,
            "No active session to abandon.\n",
            "",
        );
    }

    #[test]
    fn ui_snapshot_session_resolve_default_strategy() {
        assert_output_snapshot(
            &["session", "resolve"],
            0,
            "warning: Conflict resolution is not implemented.\nwarning: Available strategies: ours, theirs, interactive.\nRequested strategy: interactive.\n",
            "",
        );
    }
}
