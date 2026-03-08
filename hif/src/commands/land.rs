//! Land command - quick land (start session + land in one step).

use crate::cli::{
    looks_like_project_ref, parse_project_ref, LandCommand, SessionCommand, SessionSubcommand,
};
use crate::commands::session;
use crate::error::{MicError, Result};
use crate::workspace::manifest::Manifest;
use crate::workspace::session::Session;

/// Run the land command.
///
/// This is a convenience command that combines session start + land.
/// It supports two forms:
/// - In workspace: `hif land "goal"` - project inferred from workspace
/// - Outside workspace: `hif land org/project "goal"` - project explicit
pub async fn run(cmd: LandCommand) -> Result<()> {
    // Parse arguments (same logic as session start)
    let (org, project, goal) = parse_land_args(&cmd.first, cmd.second.as_deref())?;

    // Check for active session
    if Session::exists()? {
        // If there's already a session, just land it (ignore the goal)
        println!("Active session found. Landing existing session...");
        let session_cmd = SessionCommand {
            command: SessionSubcommand::Land,
        };
        return session::run(session_cmd).await;
    }

    // No active session - start one with the goal and immediately land.
    println!("Starting session and landing...");

    let start_cmd = SessionCommand {
        command: SessionSubcommand::Start {
            first: format!("{}/{}", org, project),
            second: Some(goal),
        },
    };
    session::run(start_cmd).await?;

    // Land immediately
    let session_cmd = SessionCommand {
        command: SessionSubcommand::Land,
    };
    session::run(session_cmd).await
}

/// Parse land arguments.
///
/// Supports two forms:
/// - In workspace: `hif land "goal"` - project inferred from workspace
/// - Outside workspace: `hif land org/project "goal"` - project explicit
fn parse_land_args(first: &str, second: Option<&str>) -> Result<(String, String, String)> {
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
                    "Missing goal. Usage: hif land <org/project> \"<goal>\"".to_string(),
                ));
            }

            // Try to infer project from workspace
            let manifest = Manifest::find_and_load().map_err(|_| {
                MicError::NotInWorkspace(
                    "Not in a workspace. Either:\n  \
                     1. Run from inside a workspace (created with 'hif checkout'), or\n  \
                     2. Specify the project: hif land <org/project> \"<goal>\""
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
