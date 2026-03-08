//! CLI argument parsing and command definitions.
//!
//! This module defines all CLI commands and their arguments using clap.
//! The CLI is designed to be self-documenting for both humans and AI agents.

use clap::{Parser, Subcommand};

/// The hif CLI - a forge-first version control system for the agent era
///
/// hif is an alternative to Git designed for AI-assisted development.
/// Instead of commits, you work in sessions with goals, conversations,
/// and decisions. The forge (server) is the source of truth.
#[derive(Parser, Debug)]
#[command(name = "hif")]
#[command(author, version, about, long_about = None)]
#[command(propagate_version = true)]
#[command(after_help = "\
QUICK START:
    hif auth login
    hif checkout <org/repository>
    hif session start \"<goal>\"
    hif session land
")]
pub struct Cli {
    /// Output in JSON format (for scripting and agents)
    #[arg(long, global = true)]
    pub json: bool,

    /// Verbose output (show additional details)
    #[arg(short, long, global = true)]
    pub verbose: bool,

    /// Disable colored output
    #[arg(long, global = true)]
    pub no_color: bool,

    /// Run as if started in <PATH> instead of current directory
    #[arg(short = 'C', long, global = true, value_name = "PATH")]
    pub cwd: Option<std::path::PathBuf>,

    /// Output full CLI documentation as JSON (for website generation)
    #[arg(long, hide = true)]
    pub docs: bool,

    #[command(subcommand)]
    pub command: Option<Commands>,
}

impl Cli {
    /// Get the working directory (--cwd or current directory)
    #[allow(dead_code)]
    pub fn working_dir(&self) -> std::io::Result<std::path::PathBuf> {
        match &self.cwd {
            Some(path) => Ok(path.clone()),
            None => std::env::current_dir(),
        }
    }

    /// Change to the specified working directory if --cwd was provided
    pub fn apply_cwd(&self) -> std::io::Result<()> {
        if let Some(path) = &self.cwd {
            std::env::set_current_dir(path)?;
        }
        Ok(())
    }
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    // =========================================================================
    // Authentication
    // =========================================================================
    /// Authenticate with a Micelio forge
    #[command(after_help = "\
EXAMPLES:
    $ hif auth login     # Start device flow authentication
    $ hif auth status    # Check if authenticated
    $ hif auth logout    # Remove stored credentials

NOTES:
    Authentication uses OAuth 2.0 Device Flow. You'll be given a URL
    to open in your browser and a code to enter.
")]
    Auth(AuthCommand),

    // =========================================================================
    // Organization & Repository Management
    // =========================================================================
    /// Manage organizations
    #[command(after_help = "\
EXAMPLES:
    $ hif org list        # List organizations you belong to
    $ hif org info acme   # Get details about 'acme' organization
")]
    Org(OrgCommand),

    /// Manage repositories
    #[command(after_help = "\
EXAMPLES:
    $ hif repository list acme                        # List repositories in org
    $ hif repository create acme/myapp \"My App\"       # Create new repository
    $ hif repository info acme/myapp                  # Get repository details
    $ hif repository delete acme/myapp                # Delete repository

NOTES:
    Repositories are always referenced as org/repository (e.g., 'acme/myapp').
")]
    Repository(RepositoryCommand),

    // =========================================================================
    // Workspace Commands
    // =========================================================================
    /// Create a local workspace from a repository
    #[command(after_help = "\
EXAMPLES:
    $ hif checkout acme/myapp              # Creates ./myapp directory
    $ hif checkout acme/myapp --path app   # Creates ./app directory

NEXT STEPS:
    $ cd myapp
    $ hif session start \"Add feature\"     # Start working
    $ hif status                           # See local changes
")]
    Checkout(CheckoutCommand),

    /// Link current directory to a repository
    #[command(after_help = "\
EXAMPLES:
    $ cd my-existing-code
    $ hif link acme/myapp    # Link this directory to the repository

NOTES:
    Use this when you have existing code to track.
    Unlike checkout, link doesn't download files.
")]
    Link(LinkCommand),

    /// Show workspace status and local changes
    #[command(after_help = "\
EXAMPLES:
    $ hif status          # Show all changes
    $ hif status --json   # Output as JSON (for scripts/agents)

OUTPUT:
    A = Added file
    M = Modified file  
    D = Deleted file

NOTES:
    Run from within a workspace (created by checkout or link).
")]
    Status,

    /// Sync workspace with latest changes from forge
    #[command(after_help = "\
EXAMPLES:
    $ hif sync                      # Interactive conflict resolution
    $ hif sync --strategy ours      # Keep local changes on conflict
    $ hif sync --strategy theirs    # Use remote changes on conflict
")]
    Sync(SyncCommand),

    // =========================================================================
    // Session Commands
    // =========================================================================
    /// Manage work sessions
    #[command(after_help = "\
WORKFLOW:
    $ hif session start \"Add feature\"    # Start (repository inferred from workspace)
    $ # ... make changes ...
    $ hif session note \"Decided X\"       # Document decisions
    $ hif session land                    # Push to forge

EXAMPLES:
    $ hif session start \"Fix bug\"              # In a workspace
    $ hif session start acme/myapp \"Fix bug\"   # Outside workspace
    $ hif session status                        # View current session
    $ hif session note \"Found root cause\"     # Add context
    $ hif session land                          # Push changes
    $ hif session abandon                       # Discard session

WHY SESSIONS?
    Sessions capture not just WHAT changed, but WHY. The goal,
    conversation, and decisions help future developers (and AI)
    understand the context behind changes.
")]
    Session(SessionCommand),

    /// Quick land: start session + land in one step
    #[command(after_help = "\
EXAMPLES:
    $ hif land \"Fix typo\"              # In a workspace
    $ hif land acme/myapp \"Fix typo\"   # Outside workspace

EQUIVALENT TO:
    $ hif session start \"Fix typo\"
    $ hif session land

WHEN TO USE:
    • Small, self-explanatory changes
    • Quick fixes where context is obvious
    
    For larger changes, use 'hif session start' to add notes
    and document decisions along the way.
")]
    Land(LandCommand),

    // =========================================================================
    // Content Commands (no checkout needed)
    // =========================================================================
    /// Show file contents from the forge
    #[command(after_help = "\
EXAMPLES:
    $ hif show acme/myapp README.md           # Current version
    $ hif show acme/myapp src/main.rs -r @0123456789abcdef...  # At revision hash
    $ hif show acme/myapp config.json --json  # Output as JSON

NOTES:
    Reads directly from forge - no local workspace needed.
")]
    Show(ShowCommand),

    /// List directory contents from the forge
    #[command(after_help = "\
EXAMPLES:
    $ hif tree acme/myapp                # List repository root
    $ hif tree acme/myapp src            # List src/ directory
    $ hif tree acme/myapp --ref @0123456789abcdef...  # At revision hash

NOTES:
    Reads directly from forge - no local workspace needed.
")]
    Tree(TreeCommand),

    /// Search repository content (remote index with optional local fallback)
    #[command(after_help = "\
EXAMPLES:
    $ hif grep acme/myapp \"TODO\"                     # Remote indexed search
    $ hif grep acme/myapp \"panic!\" --path src/       # Restrict to path prefix
    $ hif grep acme/myapp \"fn\\s+main\" --regex        # Regex search
    $ hif grep acme/myapp \"hello\" --position @0123456789abcdef...  # Query at revision
    $ hif grep acme/myapp \"TODO\" --local              # Fallback to local grep if remote fails

NOTES:
    Without --local, this command requires remote SearchService support.
")]
    Grep(GrepCommand),

    // =========================================================================
    // History Commands
    // =========================================================================
    /// Show session history for a repository
    #[command(after_help = "\
EXAMPLES:
    $ hif log acme/myapp              # Recent sessions
    $ hif log acme/myapp -n 50        # Last 50 sessions
    $ hif log acme/myapp --path src/  # Sessions that touched src/
")]
    Log(LogCommand),

    /// Show who changed each line (session attribution)
    #[command(after_help = "\
EXAMPLES:
    $ hif blame acme/myapp src/main.rs

OUTPUT:
    Each line shows: session_id | author | date | content
")]
    Blame(BlameCommand),

    /// Show changes between revisions
    #[command(after_help = "\
EXAMPLES:
    $ hif diff acme/myapp @<from_hash> @<to_hash>  # Between two revisions
    $ hif diff acme/myapp @<from_hash>              # From revision to HEAD
")]
    Diff(DiffCommand),

    // =========================================================================
    // Experimental
    // =========================================================================
    /// Mount repository as virtual filesystem (experimental)
    #[command(hide = true)]
    Mount(MountCommand),

    /// Unmount a mounted repository
    #[command(hide = true)]
    Unmount(UnmountCommand),
}

// =============================================================================
// Auth Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct AuthCommand {
    #[command(subcommand)]
    pub command: AuthSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum AuthSubcommand {
    /// Authenticate via device flow (opens browser)
    Login,
    /// Show current authentication status
    Status,
    /// Remove stored credentials
    Logout,
}

// =============================================================================
// Org Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct OrgCommand {
    #[command(subcommand)]
    pub command: OrgSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum OrgSubcommand {
    /// List organizations you belong to
    List,
    /// Get organization details
    Info {
        /// Organization handle (e.g., 'acme')
        org: String,
    },
}

// =============================================================================
// Repository Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct RepositoryCommand {
    #[command(subcommand)]
    pub command: RepositorySubcommand,
}

#[derive(Subcommand, Debug)]
pub enum RepositorySubcommand {
    /// List repositories in an organization
    List {
        /// Organization handle
        org: String,
    },
    /// Create a new repository
    Create {
        /// Repository reference (org/repository)
        #[arg(value_name = "ORG/REPOSITORY")]
        repository: String,
        /// Repository display name
        name: String,
        /// Repository description
        #[arg(short, long)]
        description: Option<String>,
    },
    /// Get repository details
    Info {
        /// Repository reference (org/repository)
        #[arg(value_name = "ORG/REPOSITORY")]
        repository: String,
    },
    /// Update a repository
    Update {
        /// Repository reference (org/repository)
        #[arg(value_name = "ORG/REPOSITORY")]
        repository: String,
        /// New display name
        #[arg(short, long)]
        name: Option<String>,
        /// New description
        #[arg(short, long)]
        description: Option<String>,
    },
    /// Delete a repository (cannot be undone)
    Delete {
        /// Repository reference (org/repository)
        #[arg(value_name = "ORG/REPOSITORY")]
        repository: String,
    },
}

// =============================================================================
// Workspace Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct CheckoutCommand {
    /// Repository reference (org/repository)
    #[arg(value_name = "ORG/REPOSITORY")]
    pub repository: String,

    /// Local directory path (defaults to repository name)
    #[arg(short, long)]
    pub path: Option<String>,
}

#[derive(Parser, Debug)]
pub struct LinkCommand {
    /// Repository reference (org/repository)
    #[arg(value_name = "ORG/REPOSITORY")]
    pub repository: String,
}

#[derive(Parser, Debug)]
pub struct SyncCommand {
    /// Conflict resolution strategy
    #[arg(short, long, default_value = "interactive")]
    #[arg(value_parser = ["ours", "theirs", "interactive"])]
    pub strategy: String,
}

// =============================================================================
// Session Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct SessionCommand {
    #[command(subcommand)]
    pub command: SessionSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum SessionSubcommand {
    /// Start a new session
    Start {
        /// Session goal, or org/repository + goal if outside workspace
        #[arg(value_name = "GOAL or ORG/REPOSITORY")]
        first: String,
        /// Session goal (when first arg is org/repository)
        second: Option<String>,
    },
    /// Show current session status
    Status,
    /// Add a note to the current session
    Note {
        /// Note message
        message: String,
        /// Role: human or agent
        #[arg(short, long, default_value = "human")]
        role: String,
    },
    /// Land the session (push to forge)
    Land,
    /// Abandon the session (discard changes)
    Abandon,
    /// Resolve conflicts interactively
    Resolve {
        /// Resolution strategy
        #[arg(short, long, default_value = "interactive")]
        strategy: String,
    },
}

#[derive(Parser, Debug)]
pub struct LandCommand {
    /// Session goal, or org/repository + goal if outside workspace
    #[arg(value_name = "GOAL or ORG/REPOSITORY")]
    pub first: String,
    /// Session goal (when first arg is org/repository)
    pub second: Option<String>,
}

// =============================================================================
// Content Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct ShowCommand {
    /// Repository reference (org/repository)
    #[arg(value_name = "ORG/REPOSITORY")]
    pub repository: String,
    /// File path
    pub path: String,
    /// Revision reference (64-hex hash, @latest, or HEAD)
    #[arg(short, long, value_name = "REF")]
    pub r#ref: Option<String>,
}

#[derive(Parser, Debug)]
pub struct TreeCommand {
    /// Repository reference (org/repository)
    #[arg(value_name = "ORG/REPOSITORY")]
    pub repository: String,
    /// Directory path (defaults to root)
    pub path: Option<String>,
    /// Revision reference (64-hex hash, @latest, or HEAD)
    #[arg(short, long, value_name = "REF")]
    pub r#ref: Option<String>,
}

#[derive(Parser, Debug)]
pub struct GrepCommand {
    /// Repository reference (org/repository)
    #[arg(value_name = "ORG/REPOSITORY")]
    pub repository: String,
    /// Query string or pattern
    pub query: String,
    /// Revision reference (64-hex hash, @latest, or HEAD)
    #[arg(long, value_name = "REF")]
    pub position: Option<String>,
    /// Restrict search to path prefix
    #[arg(long, value_name = "PATH_PREFIX")]
    pub path: Option<String>,
    /// Treat query as regex
    #[arg(long)]
    pub regex: bool,
    /// Case-sensitive search (default: case-insensitive)
    #[arg(long)]
    pub case_sensitive: bool,
    /// Allow local filesystem fallback when remote search fails
    #[arg(long)]
    pub local: bool,
    /// Maximum matches to return (1-500)
    #[arg(short = 'n', long, default_value = "20")]
    pub limit: u32,
}

// =============================================================================
// History Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct LogCommand {
    /// Repository reference (org/repository)
    #[arg(value_name = "ORG/REPOSITORY")]
    pub repository: String,
    /// Filter by file path
    #[arg(short, long)]
    pub path: Option<String>,
    /// Maximum number of sessions to show
    #[arg(short = 'n', long, default_value = "20")]
    pub limit: u32,
}

#[derive(Parser, Debug)]
pub struct BlameCommand {
    /// Repository reference (org/repository)
    #[arg(value_name = "ORG/REPOSITORY")]
    pub repository: String,
    /// File path
    pub path: String,
}

#[derive(Parser, Debug)]
pub struct DiffCommand {
    /// Repository reference (org/repository)
    #[arg(value_name = "ORG/REPOSITORY")]
    pub repository: String,
    /// Starting revision hash (e.g., @0123...abcd)
    pub from: String,
    /// Ending revision hash (default: HEAD)
    pub to: Option<String>,
}

// =============================================================================
// Experimental Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct MountCommand {
    /// Repository reference (org/repository)
    #[arg(value_name = "ORG/REPOSITORY")]
    pub repository: String,
    /// Mount point directory
    #[arg(short, long)]
    pub path: Option<String>,
    /// NFS port
    #[arg(short = 'P', long, default_value = "20490")]
    pub port: u16,
}

#[derive(Parser, Debug)]
pub struct UnmountCommand {
    /// Mount point directory
    pub path: String,
}

// =============================================================================
// Utilities
// =============================================================================

/// Parse a repository reference (org/repository) into (org, repository).
pub fn parse_repository_ref(s: &str) -> Option<(&str, &str)> {
    let parts: Vec<&str> = s.splitn(2, '/').collect();
    if parts.len() == 2 && !parts[0].is_empty() && !parts[1].is_empty() {
        Some((parts[0], parts[1]))
    } else {
        None
    }
}

/// Check if a string looks like a repository reference (contains '/').
pub fn looks_like_repository_ref(s: &str) -> bool {
    s.contains('/') && parse_repository_ref(s).is_some()
}

// =============================================================================
// Help JSON (for agents)
// =============================================================================

/// Generate machine-readable help for agents.
pub fn generate_help_json() -> serde_json::Value {
    serde_json::json!({
        "name": "hif",
        "version": env!("CARGO_PKG_VERSION"),
        "description": "The hif CLI - a forge-first version control system",

        "concepts": {
            "session": "A unit of work with a goal, conversation, and changes (replaces Git commits)",
            "workspace": "A local directory linked to a repository on the forge",
            "forge": "The server that stores all repository data (source of truth)",
            "landing": "Pushing session changes to the forge",
            "revision": "A point in repository history identified by a content hash (like Git commit SHA)"
        },

        "workflow": [
            {"step": 1, "command": "hif auth login", "description": "Authenticate with the forge"},
            {"step": 2, "command": "hif checkout <org/repository>", "description": "Create local workspace"},
            {"step": 3, "command": "hif session start \"<goal>\"", "description": "Start a session (repository inferred)"},
            {"step": 4, "action": "Edit files normally", "description": "Make your changes"},
            {"step": 5, "command": "hif session land", "description": "Push changes to forge"}
        ],

        "commands": {
            "auth": {
                "description": "Authentication",
                "subcommands": {
                    "login": {"description": "Authenticate via device flow", "requires_auth": false},
                    "status": {"description": "Check auth status", "requires_auth": false},
                    "logout": {"description": "Remove credentials", "requires_auth": false}
                }
            },
            "org": {
                "description": "Organization management",
                "subcommands": {
                    "list": {"description": "List your organizations", "requires_auth": true},
                    "info": {"description": "Get org details", "args": ["org"], "requires_auth": true}
                }
            },
            "repository": {
                "description": "Repository management",
                "subcommands": {
                    "list": {"description": "List repositories in org", "args": ["org"], "requires_auth": true},
                    "create": {"description": "Create repository", "args": ["org/repository", "name"], "requires_auth": true},
                    "info": {"description": "Get repository details", "args": ["org/repository"], "requires_auth": true},
                    "update": {"description": "Update repository", "args": ["org/repository"], "requires_auth": true},
                    "delete": {"description": "Delete repository", "args": ["org/repository"], "requires_auth": true}
                }
            },
            "checkout": {
                "description": "Create local workspace from repository",
                "args": ["org/repository"],
                "options": {"--path": "Local directory path"},
                "requires_auth": true
            },
            "link": {
                "description": "Link current directory to repository",
                "args": ["org/repository"],
                "requires_auth": true
            },
            "status": {
                "description": "Show workspace changes",
                "requires_workspace": true,
                "output_format": {"A": "Added", "M": "Modified", "D": "Deleted"}
            },
            "sync": {
                "description": "Sync with forge",
                "options": {"--strategy": "ours|theirs|interactive"},
                "requires_auth": true,
                "requires_workspace": true
            },
            "session": {
                "description": "Session management",
                "subcommands": {
                    "start": {
                        "description": "Start new session",
                        "args": ["goal"],
                        "args_outside_workspace": ["org/repository", "goal"],
                        "requires_workspace": "optional"
                    },
                    "status": {"description": "Show session status"},
                    "note": {"description": "Add note", "args": ["message"], "requires_session": true},
                    "land": {"description": "Push to forge", "requires_auth": true, "requires_session": true},
                    "abandon": {"description": "Discard session", "requires_session": true},
                    "resolve": {"description": "Resolve conflicts", "requires_session": true}
                }
            },
            "land": {
                "description": "Quick land (start + land in one step)",
                "args": ["goal"],
                "args_outside_workspace": ["org/repository", "goal"],
                "requires_auth": true,
                "requires_workspace": "optional"
            },
            "show": {
                "description": "Show file contents from forge",
                "args": ["org/repository", "path"],
                "options": {"--ref": "Revision hash (e.g., @012345...abcd)"},
                "requires_auth": true
            },
            "tree": {
                "description": "List directory from forge",
                "args": ["org/repository"],
                "options": {"path": "Directory path", "--ref": "Revision hash"},
                "requires_auth": true
            },
            "grep": {
                "description": "Search repository text",
                "args": ["org/repository", "query"],
                "options": {
                    "--position": "Revision hash (e.g., @012345...abcd)",
                    "--path": "Path prefix filter",
                    "--regex": "Interpret query as regex",
                    "--case-sensitive": "Case-sensitive matching",
                    "--local": "Fallback to local grep when remote fails",
                    "-n, --limit": "Maximum matches"
                },
                "requires_auth": true
            },
            "log": {
                "description": "Show session history",
                "args": ["org/repository"],
                "options": {"--path": "Filter by path", "-n": "Limit"},
                "requires_auth": true
            },
            "blame": {
                "description": "Show line attribution",
                "args": ["org/repository", "path"],
                "requires_auth": true
            },
            "diff": {
                "description": "Show changes between revisions",
                "args": ["org/repository", "from", "[to]"],
                "requires_auth": true
            }
        },

        "global_options": {
            "--json": "Output in JSON format",
            "--verbose": "Show additional details",
            "--no-color": "Disable colored output",
            "-C, --cwd": "Run from different directory",
            "--help": "Show help (add --json for machine-readable)"
        },

        "error_codes": {
            "not_authenticated": "Run 'hif auth login'",
            "token_expired": "Run 'hif auth login' again",
            "not_in_workspace": "Run 'hif checkout <org/repository>' first, or specify org/repository explicitly",
            "no_active_session": "Run 'hif session start \"<goal>\"' first",
            "session_already_active": "Run 'hif session land' or 'hif session abandon' first",
            "invalid_repository_ref": "Use format: org/repository (e.g., 'acme/myapp')",
            "conflicts_detected": "Run 'hif session resolve' or 'hif sync'",
            "no_web_url": "Set web_url in config.json for the server",
            "no_grpc_url": "Set grpc_url in config.json or enable discovery via /.well-known/micelio.json",
            "discovery_failed": "Check /.well-known/micelio.json or set grpc_url manually"
        },

        "repository_ref_format": {
            "pattern": "org/repository",
            "examples": ["acme/webapp", "myorg/api-server"],
            "description": "Always use org/repository format for repository references"
        }
    })
}

/// Check if JSON output should be used.
pub fn should_use_json() -> bool {
    std::env::args().any(|arg| arg == "--json")
}

// =============================================================================
// Documentation Generation (for website)
// =============================================================================

/// Generate comprehensive CLI documentation for website integration.
///
/// This outputs a JSON structure that can be consumed by the Elixir site
/// to generate reference documentation pages.
pub fn generate_docs() -> serde_json::Value {
    serde_json::json!({
        "name": "hif",
        "version": env!("CARGO_PKG_VERSION"),
        "description": "The hif CLI - a forge-first version control system for the agent era",
        "tagline": "Version control designed for AI-assisted development",

        "introduction": {
            "what": "hif is an alternative to Git designed for the agent era. Instead of commits, you work in sessions that capture not just what changed, but why.",
            "why": [
                "Sessions capture goals, conversations, and decisions alongside code changes",
                "Forge-first design means the server is the source of truth",
                "Built for AI agents to understand and contribute to codebases",
                "Simpler mental model: no staging area, no rebasing, no merge commits"
            ],
            "key_differences_from_git": {
                "unit_of_work": {"git": "Commit (snapshot)", "hif": "Session (goal + context + changes)"},
                "storage": {"git": "Distributed (.git folder)", "hif": "Forge-first (server is source of truth)"},
                "history": {"git": "DAG of commits", "hif": "Hash-addressed revision history"},
                "conflicts": {"git": "3-way merge", "hif": "Bloom filter detection + explicit resolution"}
            }
        },

        "installation": {
            "methods": [
                {"name": "Download binary", "platforms": ["macOS", "Linux", "Windows"]},
                {"name": "Build from source", "command": "cargo install hif"}
            ],
            "requirements": ["Micelio account (sign up at micelio.dev)"]
        },

        "concepts": [
            {
                "name": "Session",
                "description": "A unit of work with a goal, conversation, and file changes. Sessions replace Git commits but capture much more context.",
                "example": "hif session start \"Add user authentication\""
            },
            {
                "name": "Workspace",
                "description": "A local directory linked to a repository on the forge. Created with `hif checkout`.",
                "example": "hif checkout acme/myapp"
            },
            {
                "name": "Forge",
                "description": "The Micelio server that stores all repository data. Unlike Git, the forge is the source of truth.",
                "example": "https://micelio.dev"
            },
            {
                "name": "Landing",
                "description": "Pushing your session changes to the forge. Similar to Git push, but includes all session context.",
                "example": "hif session land"
            },
            {
                "name": "Revision",
                "description": "A point in repository history, referenced by hash (e.g., @012345...abcd).",
                "example": "hif show acme/myapp README.md --ref @012345...abcd"
            }
        ],

        "quick_start": {
            "title": "Quick Start",
            "steps": [
                {"step": 1, "title": "Authenticate", "command": "hif auth login", "description": "Opens browser for OAuth authentication"},
                {"step": 2, "title": "Create workspace", "command": "hif checkout acme/myapp", "description": "Downloads repository and creates local workspace"},
                {"step": 3, "title": "Start session", "command": "hif session start \"Add feature\"", "description": "Begin tracking your work with a goal"},
                {"step": 4, "title": "Make changes", "command": "# Edit files normally", "description": "Use your favorite editor, no staging needed"},
                {"step": 5, "title": "Land changes", "command": "hif session land", "description": "Push your session to the forge"}
            ],
            "quick_land": {
                "description": "For small changes, combine session start and land:",
                "command": "hif land \"Fix typo in README\""
            }
        },

        "commands": [
            {
                "name": "auth",
                "category": "Authentication",
                "description": "Authenticate with a Micelio forge",
                "subcommands": [
                    {
                        "name": "login",
                        "description": "Authenticate via OAuth device flow",
                        "usage": "hif auth login",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "hif auth login", "description": "Start authentication flow"}
                        ],
                        "notes": "Opens your browser to complete authentication. The CLI will wait for you to authorize."
                    },
                    {
                        "name": "status",
                        "description": "Check current authentication status",
                        "usage": "hif auth status",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "hif auth status", "description": "Show if logged in and token expiry"}
                        ]
                    },
                    {
                        "name": "logout",
                        "description": "Remove stored credentials",
                        "usage": "hif auth logout",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "hif auth logout", "description": "Clear all stored tokens"}
                        ]
                    }
                ]
            },
            {
                "name": "org",
                "category": "Organizations",
                "description": "Manage organizations",
                "subcommands": [
                    {
                        "name": "list",
                        "description": "List organizations you belong to",
                        "usage": "hif org list",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "hif org list", "description": "Show all your organizations"}
                        ]
                    },
                    {
                        "name": "info",
                        "description": "Get organization details",
                        "usage": "hif org info <ORG>",
                        "args": [
                            {"name": "org", "description": "Organization handle", "required": true}
                        ],
                        "options": [],
                        "examples": [
                            {"command": "hif org info acme", "description": "Show details for 'acme' organization"}
                        ]
                    }
                ]
            },
            {
                "name": "repository",
                "category": "Repositories",
                "description": "Manage repositories",
                "subcommands": [
                    {
                        "name": "list",
                        "description": "List repositories in an organization",
                        "usage": "hif repository list <ORG>",
                        "args": [
                            {"name": "org", "description": "Organization handle", "required": true}
                        ],
                        "options": [],
                        "examples": [
                            {"command": "hif repository list acme", "description": "List all repositories in 'acme'"}
                        ]
                    },
                    {
                        "name": "create",
                        "description": "Create a new repository",
                        "usage": "hif repository create <ORG/REPOSITORY> <NAME>",
                        "args": [
                            {"name": "org/repository", "description": "Repository reference (e.g., acme/myapp)", "required": true},
                            {"name": "name", "description": "Display name for the repository", "required": true}
                        ],
                        "options": [
                            {"name": "--description, -d", "description": "Repository description", "required": false}
                        ],
                        "examples": [
                            {"command": "hif repository create acme/api \"API Server\"", "description": "Create new repository"},
                            {"command": "hif repository create acme/api \"API Server\" -d \"REST API for mobile app\"", "description": "Create with description"}
                        ]
                    },
                    {
                        "name": "info",
                        "description": "Get repository details",
                        "usage": "hif repository info <ORG/REPOSITORY>",
                        "args": [
                            {"name": "org/repository", "description": "Repository reference", "required": true}
                        ],
                        "options": [],
                        "examples": [
                            {"command": "hif repository info acme/myapp", "description": "Show repository details"}
                        ]
                    },
                    {
                        "name": "update",
                        "description": "Update repository settings",
                        "usage": "hif repository update <ORG/REPOSITORY>",
                        "args": [
                            {"name": "org/repository", "description": "Repository reference", "required": true}
                        ],
                        "options": [
                            {"name": "--name, -n", "description": "New display name", "required": false},
                            {"name": "--description, -d", "description": "New description", "required": false}
                        ],
                        "examples": [
                            {"command": "hif repository update acme/myapp --name \"My App v2\"", "description": "Rename repository"}
                        ]
                    },
                    {
                        "name": "delete",
                        "description": "Delete a repository (cannot be undone)",
                        "usage": "hif repository delete <ORG/REPOSITORY>",
                        "args": [
                            {"name": "org/repository", "description": "Repository reference", "required": true}
                        ],
                        "options": [],
                        "examples": [
                            {"command": "hif repository delete acme/old-repository", "description": "Permanently delete repository"}
                        ],
                        "warning": "This action cannot be undone. All repository data will be permanently deleted."
                    }
                ]
            },
            {
                "name": "checkout",
                "category": "Workspace",
                "description": "Create a local workspace from a repository",
                "usage": "hif checkout <ORG/REPOSITORY>",
                "args": [
                    {"name": "org/repository", "description": "Repository reference (e.g., acme/myapp)", "required": true}
                ],
                "options": [
                    {"name": "--path, -p", "description": "Local directory path (defaults to repository name)", "required": false}
                ],
                "examples": [
                    {"command": "hif checkout acme/myapp", "description": "Checkout to ./myapp"},
                    {"command": "hif checkout acme/myapp --path ./code", "description": "Checkout to ./code"}
                ],
                "notes": "After checkout, cd into the directory and start a session to begin working."
            },
            {
                "name": "link",
                "category": "Workspace",
                "description": "Link current directory to an existing repository",
                "usage": "hif link <ORG/REPOSITORY>",
                "args": [
                    {"name": "org/repository", "description": "Repository reference", "required": true}
                ],
                "options": [],
                "examples": [
                    {"command": "cd my-existing-code && hif link acme/myapp", "description": "Link existing directory to repository"}
                ],
                "notes": "Use this when you have existing code you want to track. Unlike checkout, link doesn't download files."
            },
            {
                "name": "status",
                "category": "Workspace",
                "description": "Show workspace status and local changes",
                "usage": "hif status",
                "args": [],
                "options": [],
                "examples": [
                    {"command": "hif status", "description": "Show all local changes"},
                    {"command": "hif status --json", "description": "Output as JSON"}
                ],
                "output_format": {
                    "A": "Added - new file",
                    "M": "Modified - changed file",
                    "D": "Deleted - removed file"
                },
                "notes": "Must be run from within a workspace (created by checkout or link)."
            },
            {
                "name": "sync",
                "category": "Workspace",
                "description": "Sync workspace with latest changes from forge",
                "usage": "hif sync",
                "args": [],
                "options": [
                    {"name": "--strategy, -s", "description": "Conflict resolution strategy: ours, theirs, or interactive (default)", "required": false, "default": "interactive"}
                ],
                "examples": [
                    {"command": "hif sync", "description": "Sync with interactive conflict resolution"},
                    {"command": "hif sync --strategy ours", "description": "Keep local changes on conflict"},
                    {"command": "hif sync --strategy theirs", "description": "Use remote changes on conflict"}
                ]
            },
            {
                "name": "session",
                "category": "Sessions",
                "description": "Manage work sessions",
                "subcommands": [
                    {
                        "name": "start",
                        "description": "Start a new session",
                        "usage": "hif session start <GOAL>",
                        "usage_outside_workspace": "hif session start <ORG/REPOSITORY> <GOAL>",
                        "args": [
                            {"name": "goal", "description": "What you're trying to accomplish", "required": true}
                        ],
                        "options": [],
                        "examples": [
                            {"command": "hif session start \"Add user authentication\"", "description": "Start session (in workspace)"},
                            {"command": "hif session start acme/myapp \"Fix login bug\"", "description": "Start session (outside workspace)"}
                        ],
                        "notes": "When run inside a workspace, the repository is inferred automatically."
                    },
                    {
                        "name": "status",
                        "description": "Show current session status",
                        "usage": "hif session status",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "hif session status", "description": "Show active session details"}
                        ]
                    },
                    {
                        "name": "note",
                        "description": "Add a note to the current session",
                        "usage": "hif session note <MESSAGE>",
                        "args": [
                            {"name": "message", "description": "Note content", "required": true}
                        ],
                        "options": [
                            {"name": "--role, -r", "description": "Who is adding the note: human or agent", "required": false, "default": "human"}
                        ],
                        "examples": [
                            {"command": "hif session note \"Decided to use JWT for auth\"", "description": "Add a decision note"},
                            {"command": "hif session note \"Found the root cause\" --role agent", "description": "Add note from AI agent"}
                        ],
                        "notes": "Notes help capture context and decisions that will help future developers understand the code."
                    },
                    {
                        "name": "land",
                        "description": "Land the session (push changes to forge)",
                        "usage": "hif session land",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "hif session land", "description": "Push all changes to forge"}
                        ],
                        "notes": "If conflicts are detected, you'll be prompted to resolve them."
                    },
                    {
                        "name": "abandon",
                        "description": "Abandon the session (discard all changes)",
                        "usage": "hif session abandon",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "hif session abandon", "description": "Discard current session"}
                        ],
                        "warning": "This will discard all uncommitted changes in the session."
                    },
                    {
                        "name": "resolve",
                        "description": "Resolve conflicts interactively",
                        "usage": "hif session resolve",
                        "args": [],
                        "options": [
                            {"name": "--strategy, -s", "description": "Resolution strategy", "required": false, "default": "interactive"}
                        ],
                        "examples": [
                            {"command": "hif session resolve", "description": "Interactively resolve conflicts"}
                        ]
                    }
                ]
            },
            {
                "name": "land",
                "category": "Sessions",
                "description": "Quick land: start session + land in one step",
                "usage": "hif land <GOAL>",
                "usage_outside_workspace": "hif land <ORG/REPOSITORY> <GOAL>",
                "args": [
                    {"name": "goal", "description": "What you accomplished", "required": true}
                ],
                "options": [],
                "examples": [
                    {"command": "hif land \"Fix typo in README\"", "description": "Quick land (in workspace)"},
                    {"command": "hif land acme/myapp \"Update dependencies\"", "description": "Quick land (outside workspace)"}
                ],
                "notes": "Use for small, self-explanatory changes. For larger work, use `hif session start` to add notes along the way."
            },
            {
                "name": "show",
                "category": "Content",
                "description": "Show file contents from the forge (no checkout needed)",
                "usage": "hif show <ORG/REPOSITORY> <PATH>",
                "args": [
                    {"name": "org/repository", "description": "Repository reference", "required": true},
                    {"name": "path", "description": "File path", "required": true}
                ],
                "options": [
                    {"name": "--ref, -r", "description": "Revision reference (64-hex hash, @latest, or HEAD)", "required": false}
                ],
                "examples": [
                    {"command": "hif show acme/myapp README.md", "description": "Show current README"},
                    {"command": "hif show acme/myapp src/main.rs --ref @012345...abcd", "description": "Show file at a specific revision"}
                ],
                "notes": "Reads directly from the forge without creating a local workspace."
            },
            {
                "name": "tree",
                "category": "Content",
                "description": "List directory contents from the forge",
                "usage": "hif tree <ORG/REPOSITORY> [PATH]",
                "args": [
                    {"name": "org/repository", "description": "Repository reference", "required": true},
                    {"name": "path", "description": "Directory path (defaults to root)", "required": false}
                ],
                "options": [
                    {"name": "--ref, -r", "description": "Revision hash reference", "required": false}
                ],
                "examples": [
                    {"command": "hif tree acme/myapp", "description": "List repository root"},
                    {"command": "hif tree acme/myapp src", "description": "List src/ directory"},
                    {"command": "hif tree acme/myapp --ref @012345...abcd", "description": "List at a specific revision"}
                ]
            },
            {
                "name": "grep",
                "category": "Content",
                "description": "Search repository content",
                "usage": "hif grep <ORG/REPOSITORY> <QUERY>",
                "args": [
                    {"name": "org/repository", "description": "Repository reference", "required": true},
                    {"name": "query", "description": "Search query or regex pattern", "required": true}
                ],
                "options": [
                    {"name": "--position", "description": "Revision reference (64-hex hash, @latest, or HEAD)", "required": false},
                    {"name": "--path", "description": "Restrict to path prefix", "required": false},
                    {"name": "--regex", "description": "Treat query as regex", "required": false},
                    {"name": "--case-sensitive", "description": "Case-sensitive matching", "required": false},
                    {"name": "--local", "description": "Use local fallback when remote search fails", "required": false},
                    {"name": "-n, --limit", "description": "Maximum number of matches", "required": false, "default": "20"}
                ],
                "examples": [
                    {"command": "hif grep acme/myapp \"TODO\"", "description": "Search indexed content"},
                    {"command": "hif grep acme/myapp \"panic!\" --path src/", "description": "Restrict to src/"},
                    {"command": "hif grep acme/myapp \"fn\\\\s+main\" --regex", "description": "Regex search"},
                    {"command": "hif grep acme/myapp \"TODO\" --local", "description": "Use local fallback on remote failure"}
                ],
                "notes": "Uses forge search index by default and supports local fallback with --local."
            },
            {
                "name": "log",
                "category": "History",
                "description": "Show session history for a repository",
                "usage": "hif log <ORG/REPOSITORY>",
                "args": [
                    {"name": "org/repository", "description": "Repository reference", "required": true}
                ],
                "options": [
                    {"name": "--path, -p", "description": "Filter by file path", "required": false},
                    {"name": "-n", "description": "Maximum number of sessions to show", "required": false, "default": "20"}
                ],
                "examples": [
                    {"command": "hif log acme/myapp", "description": "Show recent sessions"},
                    {"command": "hif log acme/myapp -n 50", "description": "Show last 50 sessions"},
                    {"command": "hif log acme/myapp --path src/", "description": "Sessions that touched src/"}
                ]
            },
            {
                "name": "blame",
                "category": "History",
                "description": "Show who changed each line (session attribution)",
                "usage": "hif blame <ORG/REPOSITORY> <PATH>",
                "args": [
                    {"name": "org/repository", "description": "Repository reference", "required": true},
                    {"name": "path", "description": "File path", "required": true}
                ],
                "options": [],
                "examples": [
                    {"command": "hif blame acme/myapp src/main.rs", "description": "Show line-by-line attribution"}
                ],
                "notes": "Shows which session last modified each line, along with the session goal."
            },
            {
                "name": "diff",
                "category": "History",
                "description": "Show changes between two revisions",
                "usage": "hif diff <ORG/REPOSITORY> <FROM> [TO]",
                "args": [
                    {"name": "org/repository", "description": "Repository reference", "required": true},
                    {"name": "from", "description": "Starting revision hash (e.g., @0123...abcd)", "required": true},
                    {"name": "to", "description": "Ending revision hash (defaults to HEAD)", "required": false}
                ],
                "options": [],
                "examples": [
                    {"command": "hif diff acme/myapp @012345...abcd @89ab...cdef", "description": "Changes between two revisions"},
                    {"command": "hif diff acme/myapp @012345...abcd", "description": "Changes from revision to HEAD"}
                ]
            }
        ],

        "global_options": [
            {"name": "--json", "description": "Output in JSON format (for scripting and agents)"},
            {"name": "--verbose, -v", "description": "Show additional details"},
            {"name": "--no-color", "description": "Disable colored output"},
            {"name": "--cwd, -C", "description": "Run as if started in <PATH> instead of current directory"},
            {"name": "--help, -h", "description": "Show help information"},
            {"name": "--version, -V", "description": "Show version information"}
        ],

        "environment_variables": [
            {"name": "HIF_HOME", "description": "Override config directory", "default": "~/.hif"},
            {"name": "NO_COLOR", "description": "Disable colored output", "default": ""}
        ],

        "error_codes": [
            {"code": "not_authenticated", "message": "Not logged in", "resolution": "Run `hif auth login`"},
            {"code": "token_expired", "message": "Authentication token expired", "resolution": "Run `hif auth login` again"},
            {"code": "not_in_workspace", "message": "Not in a workspace directory", "resolution": "Run `hif checkout <org/repository>` first, or specify repository explicitly"},
            {"code": "no_active_session", "message": "No active session", "resolution": "Run `hif session start \"<goal>\"` first"},
            {"code": "session_already_active", "message": "A session is already active", "resolution": "Run `hif session land` or `hif session abandon` first"},
            {"code": "invalid_repository_ref", "message": "Invalid repository reference format", "resolution": "Use format: org/repository (e.g., 'acme/myapp')"},
            {"code": "conflicts_detected", "message": "Conflicts with upstream changes", "resolution": "Run `hif session resolve` or `hif sync`"}
        ],

        "see_also": {
            "website": "https://micelio.dev",
            "docs": "https://micelio.dev/docs",
            "api": "https://micelio.dev/docs/api"
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_repository_ref_valid() {
        assert_eq!(parse_repository_ref("acme/myapp"), Some(("acme", "myapp")));
        assert_eq!(
            parse_repository_ref("org/repository"),
            Some(("org", "repository"))
        );
        assert_eq!(parse_repository_ref("a/b"), Some(("a", "b")));
    }

    #[test]
    fn test_parse_repository_ref_invalid() {
        assert_eq!(parse_repository_ref("noslash"), None);
        assert_eq!(parse_repository_ref("/repository"), None);
        assert_eq!(parse_repository_ref("org/"), None);
        assert_eq!(parse_repository_ref(""), None);
        assert_eq!(parse_repository_ref("/"), None);
    }

    #[test]
    fn test_looks_like_repository_ref() {
        assert!(looks_like_repository_ref("acme/myapp"));
        assert!(!looks_like_repository_ref("just-a-goal"));
        assert!(!looks_like_repository_ref("Fix the bug"));
    }
}
