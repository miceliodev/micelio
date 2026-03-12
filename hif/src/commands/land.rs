//! Land command - quick land (start session + land in one step).

use crate::cli::{
    looks_like_repository_ref, parse_repository_ref, LandCommand, SessionCommand, SessionSubcommand,
};
use crate::commands::session;
use crate::error::{MicError, Result};
use crate::output;
use crate::workspace::manifest::Manifest;
use crate::workspace::session::Session;

/// Run the land command.
///
/// This is a convenience command that combines session start + land.
/// It supports two forms:
/// - In workspace: `hif land "goal"` - repository inferred from workspace
/// - Outside workspace: `hif land account/repository "goal"` - repository explicit
pub async fn run(cmd: LandCommand) -> Result<()> {
    // Parse arguments (same logic as session start)
    let (org, repository, goal) = parse_land_args(&cmd.first, cmd.second.as_deref())?;

    // Check for active session
    if Session::exists()? {
        // If there's already a session, just land it (ignore the goal)
        if !output::use_json() {
            println!("Active session found; landing existing session.");
        }
        let session_cmd = SessionCommand {
            command: SessionSubcommand::Land,
        };
        return session::run(session_cmd).await;
    }

    // No active session - start one with the goal and immediately land.
    if !output::use_json() {
        println!("Starting session and landing.");
    }

    let start_cmd = SessionCommand {
        command: SessionSubcommand::Start {
            first: format!("{}/{}", org, repository),
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
/// - In workspace: `hif land "goal"` - repository inferred from workspace
/// - Outside workspace: `hif land account/repository "goal"` - repository explicit
fn parse_land_args(first: &str, second: Option<&str>) -> Result<(String, String, String)> {
    match second {
        // Two args: first is account/repository, second is goal
        Some(goal) => {
            let (org, repository) = parse_repository_ref(first).ok_or_else(|| {
                MicError::InvalidRepositoryRef(format!(
                    "Invalid repository reference '{}'. Use format: account/repository",
                    first
                ))
            })?;
            Ok((org.to_string(), repository.to_string(), goal.to_string()))
        }
        // One arg: could be just goal (in workspace) or error
        None => {
            // Check if first arg looks like a repository reference
            if looks_like_repository_ref(first) {
                return Err(MicError::Other(
                    "Missing goal. Usage: hif land <account/repository> \"<goal>\"".to_string(),
                ));
            }

            // Try to infer repository from workspace
            let manifest = Manifest::find_and_load().map_err(|_| {
                MicError::NotInWorkspace(
                    "Not in a workspace. Either:\n  \
                     1. Run from inside a workspace (created with 'hif checkout'), or\n  \
                     2. Specify the repository: hif land <account/repository> \"<goal>\""
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
