//! Status command - show workspace changes.

use crate::error::{MicError, Result};
use crate::workspace::{collect_changes, session::Session, ChangeType, WorkspaceManifest};
use colored::Colorize;

/// Run the status command.
pub async fn run() -> Result<()> {
    let cwd = std::env::current_dir()?;

    // Check if we're in a workspace
    let manifest = WorkspaceManifest::load()?.ok_or(MicError::NoWorkspace)?;

    println!(
        "{}",
        format!("On repository {}/{}", manifest.account, manifest.repository).bold()
    );
    println!("Server: {}", manifest.server.dimmed());

    // Get workspace changes from disk
    let disk_changes = collect_changes(&cwd, &manifest)?;

    // Check for active session
    if let Some(state) = Session::load()? {
        println!();
        println!("{}", format!("Session: {}", state.id).cyan());
        println!("Goal: {}", state.goal);

        // Show session files (staged changes)
        if !state.files.is_empty() {
            println!();
            println!("{}", "Staged changes:".green());
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
            println!("{}", "Unstaged changes:".yellow());
            for change in &unstaged {
                let prefix = match change.change_type {
                    ChangeType::Added => "A".green(),
                    ChangeType::Modified => "M".yellow(),
                    ChangeType::Deleted => "D".red(),
                };
                println!("  {} {}", prefix, change.path);
            }
            println!();
            println!("Use your editor to continue changes, then run 'hif session land'.");
        }

        if state.files.is_empty() && unstaged.is_empty() {
            println!();
            println!("No changes.");
        }
    } else {
        // No active session
        if !disk_changes.is_empty() {
            println!();
            println!("{}", "Changes not in a session:".yellow());
            for change in &disk_changes {
                let prefix = match change.change_type {
                    ChangeType::Added => "A".green(),
                    ChangeType::Modified => "M".yellow(),
                    ChangeType::Deleted => "D".red(),
                };
                println!("  {} {}", prefix, change.path);
            }
            println!();
            println!(
                "Start a session with: {} {} {} \"goal\"",
                "hif session start".cyan(),
                manifest.account,
                manifest.repository
            );
        } else {
            println!();
            println!("{}", "No changes.".dimmed());
            println!();
            println!(
                "Start a session with: {} {} {} \"goal\"",
                "hif session start".cyan(),
                manifest.account,
                manifest.repository
            );
        }
    }

    Ok(())
}
