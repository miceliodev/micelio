//! Status command - show workspace changes.

use crate::error::{MicError, Result};
use crate::output;
use crate::workspace::{collect_changes, session::Session, ChangeType, WorkspaceManifest};
use colored::Colorize;
use serde::Serialize;

#[derive(Serialize)]
pub(crate) struct StatusWorkspaceOutput {
    account: String,
    repository: String,
    server: String,
}

#[derive(Serialize)]
pub(crate) struct StatusSessionOutput {
    id: String,
    goal: String,
}

#[derive(Serialize)]
pub(crate) struct StatusFileChangeOutput {
    path: String,
    change_type: String,
}

#[derive(Serialize)]
pub(crate) struct StatusOutput {
    workspace: StatusWorkspaceOutput,
    #[serde(skip_serializing_if = "Option::is_none")]
    session: Option<StatusSessionOutput>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    staged_changes: Vec<StatusFileChangeOutput>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    unstaged_changes: Vec<StatusFileChangeOutput>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    changes: Vec<StatusFileChangeOutput>,
}

/// Run the status command.
pub async fn run() -> Result<()> {
    let cwd = std::env::current_dir()?;
    let json_output = output::use_json();

    // Check if we're in a workspace
    let manifest = WorkspaceManifest::load()?.ok_or(MicError::NoWorkspace)?;

    if !json_output {
        println!(
            "{}",
            format!("On repository {}/{}", manifest.account, manifest.repository).bold()
        );
        println!("server {}", manifest.server.dimmed());
    }

    // Get workspace changes from disk
    let disk_changes = collect_changes(&cwd, &manifest)?;

    if json_output {
        let workspace = StatusWorkspaceOutput {
            account: manifest.account.clone(),
            repository: manifest.repository.clone(),
            server: manifest.server.clone(),
        };

        if let Some(state) = Session::load()? {
            let staged_paths: std::collections::HashSet<_> =
                state.files.iter().map(|f| &f.path).collect();
            let unstaged = disk_changes
                .iter()
                .filter(|c| !staged_paths.contains(&c.path))
                .map(|change| StatusFileChangeOutput {
                    path: change.path.clone(),
                    change_type: change_type_label(change.change_type).to_string(),
                })
                .collect::<Vec<_>>();
            let staged = state
                .files
                .iter()
                .map(|file| StatusFileChangeOutput {
                    path: file.path.clone(),
                    change_type: file.change_type.clone(),
                })
                .collect::<Vec<_>>();

            output::print_ok(
                "status",
                StatusOutput {
                    workspace,
                    session: Some(StatusSessionOutput {
                        id: state.id,
                        goal: state.goal,
                    }),
                    staged_changes: staged,
                    unstaged_changes: unstaged,
                    changes: Vec::new(),
                },
            )?;
        } else {
            let changes = disk_changes
                .iter()
                .map(|change| StatusFileChangeOutput {
                    path: change.path.clone(),
                    change_type: change_type_label(change.change_type).to_string(),
                })
                .collect::<Vec<_>>();

            output::print_ok(
                "status",
                StatusOutput {
                    workspace,
                    session: None,
                    staged_changes: Vec::new(),
                    unstaged_changes: Vec::new(),
                    changes,
                },
            )?;
        }
        return Ok(());
    }

    // Check for active session
    if let Some(state) = Session::load()? {
        println!();
        println!("{}", format!("session {}", state.id).cyan());
        println!("goal {}", state.goal);

        // Show session files (staged changes)
        if !state.files.is_empty() {
            println!();
            println!("{}", "changes to be landed:".green());
            for file in &state.files {
                let prefix = match file.change_type.as_str() {
                    "added" => "A".green(),
                    "modified" => "M".yellow(),
                    "deleted" => "D".red(),
                    _ => "?".normal(),
                };
                println!("  {} {}", prefix, file.path);
            }
        }

        // Show unstaged disk changes
        let staged_paths: std::collections::HashSet<_> =
            state.files.iter().map(|f| &f.path).collect();
        let unstaged: Vec<_> = disk_changes
            .iter()
            .filter(|c| !staged_paths.contains(&c.path))
            .collect();

        if !unstaged.is_empty() {
            println!();
            println!("{}", "unstaged changes:".yellow());
            for change in &unstaged {
                let prefix = match change.change_type {
                    ChangeType::Added => "A".green(),
                    ChangeType::Modified => "M".yellow(),
                    ChangeType::Deleted => "D".red(),
                };
                println!("  {} {}", prefix, change.path);
            }
            println!();
            println!("run 'hif session land' when ready");
        }

        if state.files.is_empty() && unstaged.is_empty() {
            println!();
            println!("nothing to land");
        }
    } else {
        // No active session
        if !disk_changes.is_empty() {
            println!();
            println!("{}", "changes not in a session:".yellow());
            for change in &disk_changes {
                let prefix = match change.change_type {
                    ChangeType::Added => "A".green(),
                    ChangeType::Modified => "M".yellow(),
                    ChangeType::Deleted => "D".red(),
                };
                println!("  {} {}", prefix, change.path);
            }
            println!();
            println!("start a session with:");
            println!(
                "  {} {} {} \"goal\"",
                "hif session start".cyan(),
                manifest.account,
                manifest.repository
            );
        } else {
            println!();
            println!("{}", "nothing to commit".dimmed());
            println!();
            println!("start a session with:");
            println!(
                "  {} {} {} \"goal\"",
                "hif session start".cyan(),
                manifest.account,
                manifest.repository
            );
        }
    }

    Ok(())
}

fn change_type_label(change_type: ChangeType) -> &'static str {
    match change_type {
        ChangeType::Added => "added",
        ChangeType::Modified => "modified",
        ChangeType::Deleted => "deleted",
    }
}
