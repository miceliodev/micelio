//! hif - The hif CLI
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
//! hif auth login
//!
//! # Create a workspace
//! hif checkout myorg/myrepository
//!
//! # Start a session
//! hif session start myorg/myrepository "Add feature X"
//!
//! # Make changes and land
//! hif session land
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
mod output;
mod workspace;

use clap::builder::styling::{AnsiColor, Color, Style, Styles};
use clap::{ColorChoice, CommandFactory, FromArgMatches};
use cli::{Cli, Commands};
use colored::Colorize;
use config::Config;
use error::Result;
use serde::Serialize;
use std::io::IsTerminal;

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
    let use_json = has_json || cli::should_use_json();
    let color_enabled = resolve_color_enabled(&args, use_json);
    configure_color(color_enabled);

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

    let command = Cli::command()
        .color(color_choice(color_enabled))
        .styles(help_styles(color_enabled));
    let matches = command.get_matches_from(&args);
    let cli = Cli::from_arg_matches(&matches).unwrap_or_else(|err| err.exit());

    let verbose = cli.verbose;
    let use_json = cli.json || cli::should_use_json();
    if use_json && color_enabled {
        configure_color(false);
    }

    // Apply --cwd if specified
    if let Err(e) = cli.apply_cwd() {
        print_error(
            &format!("Failed to change directory: {}", e),
            "cwd_error",
            use_json,
            &[],
        );
        return 1;
    }

    // Handle no command
    let Some(command) = cli.command else {
        print_error(
            "No command provided. Run 'hif --help' for usage.",
            "no_command",
            use_json,
            &[],
        );
        return 1;
    };

    output::reset_lifecycle();

    // Run the command
    match run(command).await {
        Ok(()) => {
            let warnings = output::take_warnings();
            let success_message = output::take_success_message();

            if !use_json {
                if !warnings.is_empty() {
                    output::print_human_warnings(&warnings, false);
                }
                if let Some(message) = success_message {
                    output::print_human_success(&message);
                }
            }

            0
        }
        Err(e) => {
            let warnings = output::take_warnings();
            let _ = output::take_success_message();

            print_error(&e.to_string(), e.code(), use_json, &warnings);
            if verbose && !use_json {
                eprintln!("  Code: {}", e.code());
            }
            1
        }
    }
}

#[derive(Serialize)]
struct ErrorEnvelope<'a> {
    status: &'static str,
    code: &'a str,
    message: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    warnings: Option<&'a [String]>,
}

/// Print an error message in the appropriate format.
fn print_error(message: &str, code: &str, use_json: bool, warnings: &[String]) {
    if use_json {
        let envelope = ErrorEnvelope {
            status: "error",
            code,
            message,
            warnings: (!warnings.is_empty()).then_some(warnings),
        };

        eprintln!(
            "{}",
            serde_json::to_string_pretty(&envelope).unwrap_or_default()
        );
    } else {
        if !warnings.is_empty() {
            output::print_human_warnings(warnings, true);
        }
        eprintln!("{}: {}", "Error".red().bold(), message);
    }
}

fn configure_color(enabled: bool) {
    colored::control::set_override(enabled);
}

fn resolve_color_enabled(args: &[String], use_json: bool) -> bool {
    if use_json {
        return false;
    }

    if args.iter().any(|arg| arg == "--no-color") {
        return false;
    }

    if std::env::var_os("NO_COLOR").is_some() {
        return false;
    }

    if let Ok(config) = Config::load() {
        if !config.preferences.color {
            return false;
        }
    }

    let term_is_dumb = std::env::var("TERM")
        .map(|term| term == "dumb")
        .unwrap_or(false);
    let stdout_is_terminal = std::io::stdout().is_terminal();

    stdout_is_terminal && !term_is_dumb
}

fn color_choice(enabled: bool) -> ColorChoice {
    if enabled {
        ColorChoice::Always
    } else {
        ColorChoice::Never
    }
}

fn help_styles(enabled: bool) -> Styles {
    if !enabled {
        return Styles::plain();
    }

    Styles::styled()
        .header(
            Style::new()
                .bold()
                .fg_color(Some(Color::Ansi(AnsiColor::Blue))),
        )
        .usage(
            Style::new()
                .bold()
                .fg_color(Some(Color::Ansi(AnsiColor::Green))),
        )
        .literal(
            Style::new()
                .bold()
                .fg_color(Some(Color::Ansi(AnsiColor::Cyan))),
        )
        .placeholder(Style::new().fg_color(Some(Color::Ansi(AnsiColor::Yellow))))
        .valid(
            Style::new()
                .bold()
                .fg_color(Some(Color::Ansi(AnsiColor::Green))),
        )
        .invalid(
            Style::new()
                .bold()
                .fg_color(Some(Color::Ansi(AnsiColor::Red))),
        )
}

/// Dispatch to the appropriate command handler.
async fn run(command: Commands) -> Result<()> {
    match command {
        // Auth
        Commands::Auth(cmd) => commands::auth::run(cmd).await,

        // Organization & Repository
        Commands::Org(cmd) => commands::org::run(cmd).await,
        Commands::Repository(cmd) => commands::repository::run(cmd).await,

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
        Commands::Grep(cmd) => commands::grep::run(cmd).await,

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
