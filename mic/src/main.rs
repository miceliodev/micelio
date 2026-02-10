//! mic - The Micelio CLI
//!
//! A forge-first version control system for the agent era.
//!
//! # Architecture
//!
//! The CLI is organized into the following modules:
//!
//! - `cli`: Command-line argument parsing (clap)
//! - `commands`: Command implementations
//! - `config`: Configuration and token management
//! - `core`: Core algorithms (hash, bloom, hlc, tree)
//! - `grpc`: gRPC client for forge communication
//! - `workspace`: Local workspace management
//! - `error`: Error types and handling
//!
//! # Usage
//!
//! ```bash
//! # Authenticate
//! mic auth login
//!
//! # Create a workspace
//! mic checkout myorg/myproject
//!
//! # Start a session
//! mic session start myorg myproject "Add feature X"
//!
//! # Make changes and land
//! mic session land
//! ```

mod cache;
mod cdn;
mod cli;
mod commands;
mod config;
mod constants;
mod core;
mod error;
mod grpc;
mod http_client;
mod workspace;

use clap::Parser;
use cli::{Cli, Commands};
use colored::Colorize;
use error::Result;

fn main() {
    // Build async runtime
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("Failed to create Tokio runtime");

    // Run the CLI
    let exit_code = runtime.block_on(async_main());
    std::process::exit(exit_code);
}

async fn async_main() -> i32 {
    // Check for --help --json before clap parses (clap exits on --help)
    let args: Vec<String> = std::env::args().collect();
    let has_help = args.iter().any(|a| a == "--help" || a == "-h");
    let has_json = args.iter().any(|a| a == "--json");
    let has_docs = args.iter().any(|a| a == "--docs");
    
    // --docs outputs full documentation for website generation
    if has_docs {
        let docs = cli::generate_docs();
        println!("{}", serde_json::to_string_pretty(&docs).unwrap());
        return 0;
    }
    
    // --help --json outputs agent-friendly help
    if has_help && has_json {
        let help = cli::generate_help_json();
        println!("{}", serde_json::to_string_pretty(&help).unwrap());
        return 0;
    }

    let cli = Cli::parse();

    let use_json = cli.json || cli::should_use_json();
    let verbose = cli.verbose;

    // Apply --cwd if specified
    if let Err(e) = cli.apply_cwd() {
        print_error(&format!("Failed to change directory: {}", e), "cwd_error", use_json);
        return 1;
    }

    // Handle no command
    let Some(command) = cli.command else {
        // No command provided, show help hint
        eprintln!("No command provided. Run 'mic --help' for usage.");
        return 1;
    };

    // Run the command
    match run(command).await {
        Ok(()) => 0,
        Err(e) => {
            print_error(&e.to_string(), e.code(), use_json);
            if verbose && !use_json {
                eprintln!("  Code: {}", e.code());
            }
            1
        }
    }
}

/// Print an error message in the appropriate format.
fn print_error(message: &str, code: &str, use_json: bool) {
    if use_json {
        let json = serde_json::json!({
            "status": "error",
            "code": code,
            "message": message,
        });
        eprintln!("{}", serde_json::to_string_pretty(&json).unwrap_or_default());
    } else {
        eprintln!("{}: {}", "Error".red().bold(), message);
    }
}

/// Dispatch to the appropriate command handler.
async fn run(command: Commands) -> Result<()> {
    match command {
        // Auth
        Commands::Auth(cmd) => commands::auth::run(cmd).await,
        
        // Organization & Project
        Commands::Org(cmd) => commands::org::run(cmd).await,
        Commands::Project(cmd) => commands::project::run(cmd).await,
        
        // Workspace
        Commands::Checkout(cmd) => commands::checkout::run(cmd).await,
        Commands::Link(cmd) => commands::link::run(cmd).await,
        Commands::Status => commands::status::run().await,
        Commands::Sync(cmd) => commands::sync::run(cmd).await,
        
        // Sessions
        Commands::Session(cmd) => commands::session::run(cmd).await,
        Commands::Land(cmd) => commands::land::run(cmd).await,
        
        // Content (read from forge)
        Commands::Show(cmd) => commands::show::run(cmd).await,
        Commands::Tree(cmd) => commands::tree::run(cmd).await,
        
        // History
        Commands::Log(cmd) => commands::log::run(cmd).await,
        Commands::Blame(cmd) => commands::blame::run(cmd).await,
        Commands::Diff(cmd) => commands::diff::run(cmd).await,
        
        // Experimental (hidden)
        Commands::Mount(cmd) => commands::mount::run(cmd).await,
        Commands::Unmount(cmd) => commands::unmount::run(cmd).await,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn verify_cli() {
        // Verify the CLI definition is valid
        use clap::CommandFactory;
        Cli::command().debug_assert();
    }
}
