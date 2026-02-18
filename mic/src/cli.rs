//! CLI argument parsing and command definitions.
//!
//! This module defines all CLI commands and their arguments using clap.
//! The CLI is designed to be self-documenting for both humans and AI agents.

use clap::{Parser, Subcommand};

/// The Micelio CLI - a forge-first version control system for the agent era
///
/// mic is an alternative to Git designed for AI-assisted development.
/// Instead of commits, you work in sessions with goals, conversations,
/// and decisions. The forge (server) is the source of truth.
#[derive(Parser, Debug)]
#[command(name = "mic")]
#[command(author, version, about, long_about = None)]
#[command(propagate_version = true)]
#[command(after_help = "\
QUICK START:
    mic auth login
    mic checkout <org/project>
    mic session start \"<goal>\"
    mic session land
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
    $ mic auth login     # Start device flow authentication
    $ mic auth status    # Check if authenticated
    $ mic auth logout    # Remove stored credentials

NOTES:
    Authentication uses OAuth 2.0 Device Flow. You'll be given a URL
    to open in your browser and a code to enter.
")]
    Auth(AuthCommand),

    // =========================================================================
    // Organization & Project Management
    // =========================================================================
    
    /// Manage organizations
    #[command(after_help = "\
EXAMPLES:
    $ mic org list        # List organizations you belong to
    $ mic org info acme   # Get details about 'acme' organization
")]
    Org(OrgCommand),

    /// Manage projects
    #[command(after_help = "\
EXAMPLES:
    $ mic project list acme                        # List projects in org
    $ mic project create acme/myapp \"My App\"       # Create new project
    $ mic project info acme/myapp                  # Get project details
    $ mic project delete acme/myapp                # Delete project

NOTES:
    Projects are always referenced as org/project (e.g., 'acme/myapp').
")]
    Project(ProjectCommand),

    // =========================================================================
    // Workspace Commands
    // =========================================================================
    
    /// Create a local workspace from a project
    #[command(after_help = "\
EXAMPLES:
    $ mic checkout acme/myapp              # Creates ./myapp directory
    $ mic checkout acme/myapp --path app   # Creates ./app directory

NEXT STEPS:
    $ cd myapp
    $ mic session start \"Add feature\"     # Start working
    $ mic status                           # See local changes
")]
    Checkout(CheckoutCommand),

    /// Link current directory to a project
    #[command(after_help = "\
EXAMPLES:
    $ cd my-existing-code
    $ mic link acme/myapp    # Link this directory to the project

NOTES:
    Use this when you have existing code to track.
    Unlike checkout, link doesn't download files.
")]
    Link(LinkCommand),

    /// Show workspace status and local changes
    #[command(after_help = "\
EXAMPLES:
    $ mic status          # Show all changes
    $ mic status --json   # Output as JSON (for scripts/agents)

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
    $ mic sync                      # Interactive conflict resolution
    $ mic sync --strategy ours      # Keep local changes on conflict
    $ mic sync --strategy theirs    # Use remote changes on conflict
")]
    Sync(SyncCommand),

    // =========================================================================
    // Session Commands
    // =========================================================================
    
    /// Manage work sessions
    #[command(after_help = "\
WORKFLOW:
    $ mic session start \"Add feature\"    # Start (project inferred from workspace)
    $ # ... make changes ...
    $ mic session note \"Decided X\"       # Document decisions
    $ mic session land                    # Push to forge

EXAMPLES:
    $ mic session start \"Fix bug\"              # In a workspace
    $ mic session start acme/myapp \"Fix bug\"   # Outside workspace
    $ mic session status                        # View current session
    $ mic session note \"Found root cause\"     # Add context
    $ mic session land                          # Push changes
    $ mic session abandon                       # Discard session

WHY SESSIONS?
    Sessions capture not just WHAT changed, but WHY. The goal,
    conversation, and decisions help future developers (and AI)
    understand the context behind changes.
")]
    Session(SessionCommand),

    /// Quick land: start session + land in one step
    #[command(after_help = "\
EXAMPLES:
    $ mic land \"Fix typo\"              # In a workspace
    $ mic land acme/myapp \"Fix typo\"   # Outside workspace

EQUIVALENT TO:
    $ mic session start \"Fix typo\"
    $ mic session land

WHEN TO USE:
    • Small, self-explanatory changes
    • Quick fixes where context is obvious
    
    For larger changes, use 'mic session start' to add notes
    and document decisions along the way.
")]
    Land(LandCommand),

    // =========================================================================
    // Content Commands (no checkout needed)
    // =========================================================================
    
    /// Show file contents from the forge
    #[command(after_help = "\
EXAMPLES:
    $ mic show acme/myapp README.md           # Current version
    $ mic show acme/myapp src/main.rs -r @10  # At position 10
    $ mic show acme/myapp config.json --json  # Output as JSON

NOTES:
    Reads directly from forge - no local workspace needed.
")]
    Show(ShowCommand),

    /// List directory contents from the forge
    #[command(after_help = "\
EXAMPLES:
    $ mic tree acme/myapp                # List project root
    $ mic tree acme/myapp src            # List src/ directory
    $ mic tree acme/myapp --ref @5       # At position 5

NOTES:
    Reads directly from forge - no local workspace needed.
")]
    Tree(TreeCommand),

    // =========================================================================
    // History Commands
    // =========================================================================
    
    /// Show session history for a project
    #[command(after_help = "\
EXAMPLES:
    $ mic log acme/myapp              # Recent sessions
    $ mic log acme/myapp -n 50        # Last 50 sessions
    $ mic log acme/myapp --path src/  # Sessions that touched src/
")]
    Log(LogCommand),

    /// Show who changed each line (session attribution)
    #[command(after_help = "\
EXAMPLES:
    $ mic blame acme/myapp src/main.rs

OUTPUT:
    Each line shows: session_id | author | date | content
")]
    Blame(BlameCommand),

    /// Show changes between positions
    #[command(after_help = "\
EXAMPLES:
    $ mic diff acme/myapp @5 @10    # Changes from position 5 to 10
    $ mic diff acme/myapp @5        # Changes from position 5 to HEAD
")]
    Diff(DiffCommand),

    // =========================================================================
    // Experimental
    // =========================================================================
    
    /// Mount project as virtual filesystem (experimental)
    #[command(hide = true)]
    Mount(MountCommand),

    /// Unmount a mounted project
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
// Project Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct ProjectCommand {
    #[command(subcommand)]
    pub command: ProjectSubcommand,
}

#[derive(Subcommand, Debug)]
pub enum ProjectSubcommand {
    /// List projects in an organization
    List {
        /// Organization handle
        org: String,
    },
    /// Create a new project
    Create {
        /// Project reference (org/project)
        #[arg(value_name = "ORG/PROJECT")]
        project: String,
        /// Project display name
        name: String,
        /// Project description
        #[arg(short, long)]
        description: Option<String>,
    },
    /// Get project details
    Info {
        /// Project reference (org/project)
        #[arg(value_name = "ORG/PROJECT")]
        project: String,
    },
    /// Update a project
    Update {
        /// Project reference (org/project)
        #[arg(value_name = "ORG/PROJECT")]
        project: String,
        /// New display name
        #[arg(short, long)]
        name: Option<String>,
        /// New description
        #[arg(short, long)]
        description: Option<String>,
    },
    /// Delete a project (cannot be undone)
    Delete {
        /// Project reference (org/project)
        #[arg(value_name = "ORG/PROJECT")]
        project: String,
    },
}

// =============================================================================
// Workspace Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct CheckoutCommand {
    /// Project reference (org/project)
    #[arg(value_name = "ORG/PROJECT")]
    pub project: String,

    /// Local directory path (defaults to project name)
    #[arg(short, long)]
    pub path: Option<String>,
}

#[derive(Parser, Debug)]
pub struct LinkCommand {
    /// Project reference (org/project)
    #[arg(value_name = "ORG/PROJECT")]
    pub project: String,
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
        /// Session goal, or org/project + goal if outside workspace
        #[arg(value_name = "GOAL or ORG/PROJECT")]
        first: String,
        /// Session goal (when first arg is org/project)
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
    /// Session goal, or org/project + goal if outside workspace
    #[arg(value_name = "GOAL or ORG/PROJECT")]
    pub first: String,
    /// Session goal (when first arg is org/project)
    pub second: Option<String>,
}

// =============================================================================
// Content Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct ShowCommand {
    /// Project reference (org/project)
    #[arg(value_name = "ORG/PROJECT")]
    pub project: String,
    /// File path
    pub path: String,
    /// Position reference (e.g., @10, @latest)
    #[arg(short, long, value_name = "REF")]
    pub r#ref: Option<String>,
}

#[derive(Parser, Debug)]
pub struct TreeCommand {
    /// Project reference (org/project)
    #[arg(value_name = "ORG/PROJECT")]
    pub project: String,
    /// Directory path (defaults to root)
    pub path: Option<String>,
    /// Position reference (e.g., @10, @latest)
    #[arg(short, long, value_name = "REF")]
    pub r#ref: Option<String>,
}

// =============================================================================
// History Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct LogCommand {
    /// Project reference (org/project)
    #[arg(value_name = "ORG/PROJECT")]
    pub project: String,
    /// Filter by file path
    #[arg(short, long)]
    pub path: Option<String>,
    /// Maximum number of sessions to show
    #[arg(short = 'n', long, default_value = "20")]
    pub limit: u32,
}

#[derive(Parser, Debug)]
pub struct BlameCommand {
    /// Project reference (org/project)
    #[arg(value_name = "ORG/PROJECT")]
    pub project: String,
    /// File path
    pub path: String,
}

#[derive(Parser, Debug)]
pub struct DiffCommand {
    /// Project reference (org/project)
    #[arg(value_name = "ORG/PROJECT")]
    pub project: String,
    /// Starting position (e.g., @5)
    pub from: String,
    /// Ending position (default: HEAD)
    pub to: Option<String>,
}

// =============================================================================
// Experimental Commands
// =============================================================================

#[derive(Parser, Debug)]
pub struct MountCommand {
    /// Project reference (org/project)
    #[arg(value_name = "ORG/PROJECT")]
    pub project: String,
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

/// Parse a project reference (org/project) into (org, project).
pub fn parse_project_ref(s: &str) -> Option<(&str, &str)> {
    let parts: Vec<&str> = s.splitn(2, '/').collect();
    if parts.len() == 2 && !parts[0].is_empty() && !parts[1].is_empty() {
        Some((parts[0], parts[1]))
    } else {
        None
    }
}

/// Check if a string looks like a project reference (contains '/').
pub fn looks_like_project_ref(s: &str) -> bool {
    s.contains('/') && parse_project_ref(s).is_some()
}

// =============================================================================
// Help JSON (for agents)
// =============================================================================

/// Generate machine-readable help for agents.
pub fn generate_help_json() -> serde_json::Value {
    serde_json::json!({
        "name": "mic",
        "version": env!("CARGO_PKG_VERSION"),
        "description": "The Micelio CLI - a forge-first version control system",
        
        "concepts": {
            "session": "A unit of work with a goal, conversation, and changes (replaces Git commits)",
            "workspace": "A local directory linked to a project on the forge",
            "forge": "The server that stores all project data (source of truth)",
            "landing": "Pushing session changes to the forge",
            "position": "A point in project history (like Git commit SHA, but sequential)"
        },
        
        "workflow": [
            {"step": 1, "command": "mic auth login", "description": "Authenticate with the forge"},
            {"step": 2, "command": "mic checkout <org/project>", "description": "Create local workspace"},
            {"step": 3, "command": "mic session start \"<goal>\"", "description": "Start a session (project inferred)"},
            {"step": 4, "action": "Edit files normally", "description": "Make your changes"},
            {"step": 5, "command": "mic session land", "description": "Push changes to forge"}
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
            "project": {
                "description": "Project management",
                "subcommands": {
                    "list": {"description": "List projects in org", "args": ["org"], "requires_auth": true},
                    "create": {"description": "Create project", "args": ["org/project", "name"], "requires_auth": true},
                    "info": {"description": "Get project details", "args": ["org/project"], "requires_auth": true},
                    "update": {"description": "Update project", "args": ["org/project"], "requires_auth": true},
                    "delete": {"description": "Delete project", "args": ["org/project"], "requires_auth": true}
                }
            },
            "checkout": {
                "description": "Create local workspace from project",
                "args": ["org/project"],
                "options": {"--path": "Local directory path"},
                "requires_auth": true
            },
            "link": {
                "description": "Link current directory to project",
                "args": ["org/project"],
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
                        "args_outside_workspace": ["org/project", "goal"],
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
                "args_outside_workspace": ["org/project", "goal"],
                "requires_auth": true,
                "requires_workspace": "optional"
            },
            "show": {
                "description": "Show file contents from forge",
                "args": ["org/project", "path"],
                "options": {"--ref": "Position (e.g., @10)"},
                "requires_auth": true
            },
            "tree": {
                "description": "List directory from forge",
                "args": ["org/project"],
                "options": {"path": "Directory path", "--ref": "Position"},
                "requires_auth": true
            },
            "log": {
                "description": "Show session history",
                "args": ["org/project"],
                "options": {"--path": "Filter by path", "-n": "Limit"},
                "requires_auth": true
            },
            "blame": {
                "description": "Show line attribution",
                "args": ["org/project", "path"],
                "requires_auth": true
            },
            "diff": {
                "description": "Show changes between positions",
                "args": ["org/project", "from", "[to]"],
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
            "not_authenticated": "Run 'mic auth login'",
            "token_expired": "Run 'mic auth login' again",
            "not_in_workspace": "Run 'mic checkout <org/project>' first, or specify org/project explicitly",
            "no_active_session": "Run 'mic session start \"<goal>\"' first",
            "session_already_active": "Run 'mic session land' or 'mic session abandon' first",
            "invalid_project_ref": "Use format: org/project (e.g., 'acme/myapp')",
            "conflicts_detected": "Run 'mic session resolve' or 'mic sync'",
            "no_web_url": "Set web_url in config.json for the server",
            "no_grpc_url": "Set grpc_url in config.json or enable discovery via /.well-known/micelio.json",
            "discovery_failed": "Check /.well-known/micelio.json or set grpc_url manually"
        },
        
        "project_ref_format": {
            "pattern": "org/project",
            "examples": ["acme/webapp", "myorg/api-server"],
            "description": "Always use org/project format for project references"
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
        "name": "mic",
        "version": env!("CARGO_PKG_VERSION"),
        "description": "The Micelio CLI - a forge-first version control system for the agent era",
        "tagline": "Version control designed for AI-assisted development",
        
        "introduction": {
            "what": "mic is an alternative to Git designed for the agent era. Instead of commits, you work in sessions that capture not just what changed, but why.",
            "why": [
                "Sessions capture goals, conversations, and decisions alongside code changes",
                "Forge-first design means the server is the source of truth",
                "Built for AI agents to understand and contribute to codebases",
                "Simpler mental model: no staging area, no rebasing, no merge commits"
            ],
            "key_differences_from_git": {
                "unit_of_work": {"git": "Commit (snapshot)", "mic": "Session (goal + context + changes)"},
                "storage": {"git": "Distributed (.git folder)", "mic": "Forge-first (server is source of truth)"},
                "history": {"git": "DAG of commits", "mic": "Append-only log of landing positions"},
                "conflicts": {"git": "3-way merge", "mic": "Bloom filter detection + explicit resolution"}
            }
        },
        
        "installation": {
            "methods": [
                {"name": "Download binary", "platforms": ["macOS", "Linux", "Windows"]},
                {"name": "Build from source", "command": "cargo install mic"}
            ],
            "requirements": ["Micelio account (sign up at micelio.dev)"]
        },
        
        "concepts": [
            {
                "name": "Session",
                "description": "A unit of work with a goal, conversation, and file changes. Sessions replace Git commits but capture much more context.",
                "example": "mic session start \"Add user authentication\""
            },
            {
                "name": "Workspace", 
                "description": "A local directory linked to a project on the forge. Created with `mic checkout`.",
                "example": "mic checkout acme/myapp"
            },
            {
                "name": "Forge",
                "description": "The Micelio server that stores all project data. Unlike Git, the forge is the source of truth.",
                "example": "https://micelio.dev"
            },
            {
                "name": "Landing",
                "description": "Pushing your session changes to the forge. Similar to Git push, but includes all session context.",
                "example": "mic session land"
            },
            {
                "name": "Position",
                "description": "A point in project history, referenced as @N (e.g., @10). Similar to Git commit SHA but sequential.",
                "example": "mic show acme/myapp README.md --ref @5"
            }
        ],
        
        "quick_start": {
            "title": "Quick Start",
            "steps": [
                {"step": 1, "title": "Authenticate", "command": "mic auth login", "description": "Opens browser for OAuth authentication"},
                {"step": 2, "title": "Create workspace", "command": "mic checkout acme/myapp", "description": "Downloads project and creates local workspace"},
                {"step": 3, "title": "Start session", "command": "mic session start \"Add feature\"", "description": "Begin tracking your work with a goal"},
                {"step": 4, "title": "Make changes", "command": "# Edit files normally", "description": "Use your favorite editor, no staging needed"},
                {"step": 5, "title": "Land changes", "command": "mic session land", "description": "Push your session to the forge"}
            ],
            "quick_land": {
                "description": "For small changes, combine session start and land:",
                "command": "mic land \"Fix typo in README\""
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
                        "usage": "mic auth login",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "mic auth login", "description": "Start authentication flow"}
                        ],
                        "notes": "Opens your browser to complete authentication. The CLI will wait for you to authorize."
                    },
                    {
                        "name": "status",
                        "description": "Check current authentication status",
                        "usage": "mic auth status",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "mic auth status", "description": "Show if logged in and token expiry"}
                        ]
                    },
                    {
                        "name": "logout",
                        "description": "Remove stored credentials",
                        "usage": "mic auth logout",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "mic auth logout", "description": "Clear all stored tokens"}
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
                        "usage": "mic org list",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "mic org list", "description": "Show all your organizations"}
                        ]
                    },
                    {
                        "name": "info",
                        "description": "Get organization details",
                        "usage": "mic org info <ORG>",
                        "args": [
                            {"name": "org", "description": "Organization handle", "required": true}
                        ],
                        "options": [],
                        "examples": [
                            {"command": "mic org info acme", "description": "Show details for 'acme' organization"}
                        ]
                    }
                ]
            },
            {
                "name": "project",
                "category": "Projects",
                "description": "Manage projects",
                "subcommands": [
                    {
                        "name": "list",
                        "description": "List projects in an organization",
                        "usage": "mic project list <ORG>",
                        "args": [
                            {"name": "org", "description": "Organization handle", "required": true}
                        ],
                        "options": [],
                        "examples": [
                            {"command": "mic project list acme", "description": "List all projects in 'acme'"}
                        ]
                    },
                    {
                        "name": "create",
                        "description": "Create a new project",
                        "usage": "mic project create <ORG/PROJECT> <NAME>",
                        "args": [
                            {"name": "org/project", "description": "Project reference (e.g., acme/myapp)", "required": true},
                            {"name": "name", "description": "Display name for the project", "required": true}
                        ],
                        "options": [
                            {"name": "--description, -d", "description": "Project description", "required": false}
                        ],
                        "examples": [
                            {"command": "mic project create acme/api \"API Server\"", "description": "Create new project"},
                            {"command": "mic project create acme/api \"API Server\" -d \"REST API for mobile app\"", "description": "Create with description"}
                        ]
                    },
                    {
                        "name": "info",
                        "description": "Get project details",
                        "usage": "mic project info <ORG/PROJECT>",
                        "args": [
                            {"name": "org/project", "description": "Project reference", "required": true}
                        ],
                        "options": [],
                        "examples": [
                            {"command": "mic project info acme/myapp", "description": "Show project details"}
                        ]
                    },
                    {
                        "name": "update",
                        "description": "Update project settings",
                        "usage": "mic project update <ORG/PROJECT>",
                        "args": [
                            {"name": "org/project", "description": "Project reference", "required": true}
                        ],
                        "options": [
                            {"name": "--name, -n", "description": "New display name", "required": false},
                            {"name": "--description, -d", "description": "New description", "required": false}
                        ],
                        "examples": [
                            {"command": "mic project update acme/myapp --name \"My App v2\"", "description": "Rename project"}
                        ]
                    },
                    {
                        "name": "delete",
                        "description": "Delete a project (cannot be undone)",
                        "usage": "mic project delete <ORG/PROJECT>",
                        "args": [
                            {"name": "org/project", "description": "Project reference", "required": true}
                        ],
                        "options": [],
                        "examples": [
                            {"command": "mic project delete acme/old-project", "description": "Permanently delete project"}
                        ],
                        "warning": "This action cannot be undone. All project data will be permanently deleted."
                    }
                ]
            },
            {
                "name": "checkout",
                "category": "Workspace",
                "description": "Create a local workspace from a project",
                "usage": "mic checkout <ORG/PROJECT>",
                "args": [
                    {"name": "org/project", "description": "Project reference (e.g., acme/myapp)", "required": true}
                ],
                "options": [
                    {"name": "--path, -p", "description": "Local directory path (defaults to project name)", "required": false}
                ],
                "examples": [
                    {"command": "mic checkout acme/myapp", "description": "Checkout to ./myapp"},
                    {"command": "mic checkout acme/myapp --path ./code", "description": "Checkout to ./code"}
                ],
                "notes": "After checkout, cd into the directory and start a session to begin working."
            },
            {
                "name": "link",
                "category": "Workspace",
                "description": "Link current directory to an existing project",
                "usage": "mic link <ORG/PROJECT>",
                "args": [
                    {"name": "org/project", "description": "Project reference", "required": true}
                ],
                "options": [],
                "examples": [
                    {"command": "cd my-existing-code && mic link acme/myapp", "description": "Link existing directory to project"}
                ],
                "notes": "Use this when you have existing code you want to track. Unlike checkout, link doesn't download files."
            },
            {
                "name": "status",
                "category": "Workspace",
                "description": "Show workspace status and local changes",
                "usage": "mic status",
                "args": [],
                "options": [],
                "examples": [
                    {"command": "mic status", "description": "Show all local changes"},
                    {"command": "mic status --json", "description": "Output as JSON"}
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
                "usage": "mic sync",
                "args": [],
                "options": [
                    {"name": "--strategy, -s", "description": "Conflict resolution strategy: ours, theirs, or interactive (default)", "required": false, "default": "interactive"}
                ],
                "examples": [
                    {"command": "mic sync", "description": "Sync with interactive conflict resolution"},
                    {"command": "mic sync --strategy ours", "description": "Keep local changes on conflict"},
                    {"command": "mic sync --strategy theirs", "description": "Use remote changes on conflict"}
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
                        "usage": "mic session start <GOAL>",
                        "usage_outside_workspace": "mic session start <ORG/PROJECT> <GOAL>",
                        "args": [
                            {"name": "goal", "description": "What you're trying to accomplish", "required": true}
                        ],
                        "options": [],
                        "examples": [
                            {"command": "mic session start \"Add user authentication\"", "description": "Start session (in workspace)"},
                            {"command": "mic session start acme/myapp \"Fix login bug\"", "description": "Start session (outside workspace)"}
                        ],
                        "notes": "When run inside a workspace, the project is inferred automatically."
                    },
                    {
                        "name": "status",
                        "description": "Show current session status",
                        "usage": "mic session status",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "mic session status", "description": "Show active session details"}
                        ]
                    },
                    {
                        "name": "note",
                        "description": "Add a note to the current session",
                        "usage": "mic session note <MESSAGE>",
                        "args": [
                            {"name": "message", "description": "Note content", "required": true}
                        ],
                        "options": [
                            {"name": "--role, -r", "description": "Who is adding the note: human or agent", "required": false, "default": "human"}
                        ],
                        "examples": [
                            {"command": "mic session note \"Decided to use JWT for auth\"", "description": "Add a decision note"},
                            {"command": "mic session note \"Found the root cause\" --role agent", "description": "Add note from AI agent"}
                        ],
                        "notes": "Notes help capture context and decisions that will help future developers understand the code."
                    },
                    {
                        "name": "land",
                        "description": "Land the session (push changes to forge)",
                        "usage": "mic session land",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "mic session land", "description": "Push all changes to forge"}
                        ],
                        "notes": "If conflicts are detected, you'll be prompted to resolve them."
                    },
                    {
                        "name": "abandon",
                        "description": "Abandon the session (discard all changes)",
                        "usage": "mic session abandon",
                        "args": [],
                        "options": [],
                        "examples": [
                            {"command": "mic session abandon", "description": "Discard current session"}
                        ],
                        "warning": "This will discard all uncommitted changes in the session."
                    },
                    {
                        "name": "resolve",
                        "description": "Resolve conflicts interactively",
                        "usage": "mic session resolve",
                        "args": [],
                        "options": [
                            {"name": "--strategy, -s", "description": "Resolution strategy", "required": false, "default": "interactive"}
                        ],
                        "examples": [
                            {"command": "mic session resolve", "description": "Interactively resolve conflicts"}
                        ]
                    }
                ]
            },
            {
                "name": "land",
                "category": "Sessions",
                "description": "Quick land: start session + land in one step",
                "usage": "mic land <GOAL>",
                "usage_outside_workspace": "mic land <ORG/PROJECT> <GOAL>",
                "args": [
                    {"name": "goal", "description": "What you accomplished", "required": true}
                ],
                "options": [],
                "examples": [
                    {"command": "mic land \"Fix typo in README\"", "description": "Quick land (in workspace)"},
                    {"command": "mic land acme/myapp \"Update dependencies\"", "description": "Quick land (outside workspace)"}
                ],
                "notes": "Use for small, self-explanatory changes. For larger work, use `mic session start` to add notes along the way."
            },
            {
                "name": "show",
                "category": "Content",
                "description": "Show file contents from the forge (no checkout needed)",
                "usage": "mic show <ORG/PROJECT> <PATH>",
                "args": [
                    {"name": "org/project", "description": "Project reference", "required": true},
                    {"name": "path", "description": "File path", "required": true}
                ],
                "options": [
                    {"name": "--ref, -r", "description": "Position reference (e.g., @10, @latest)", "required": false}
                ],
                "examples": [
                    {"command": "mic show acme/myapp README.md", "description": "Show current README"},
                    {"command": "mic show acme/myapp src/main.rs --ref @10", "description": "Show file at position 10"}
                ],
                "notes": "Reads directly from the forge without creating a local workspace."
            },
            {
                "name": "tree",
                "category": "Content",
                "description": "List directory contents from the forge",
                "usage": "mic tree <ORG/PROJECT> [PATH]",
                "args": [
                    {"name": "org/project", "description": "Project reference", "required": true},
                    {"name": "path", "description": "Directory path (defaults to root)", "required": false}
                ],
                "options": [
                    {"name": "--ref, -r", "description": "Position reference", "required": false}
                ],
                "examples": [
                    {"command": "mic tree acme/myapp", "description": "List project root"},
                    {"command": "mic tree acme/myapp src", "description": "List src/ directory"},
                    {"command": "mic tree acme/myapp --ref @5", "description": "List at position 5"}
                ]
            },
            {
                "name": "log",
                "category": "History",
                "description": "Show session history for a project",
                "usage": "mic log <ORG/PROJECT>",
                "args": [
                    {"name": "org/project", "description": "Project reference", "required": true}
                ],
                "options": [
                    {"name": "--path, -p", "description": "Filter by file path", "required": false},
                    {"name": "-n", "description": "Maximum number of sessions to show", "required": false, "default": "20"}
                ],
                "examples": [
                    {"command": "mic log acme/myapp", "description": "Show recent sessions"},
                    {"command": "mic log acme/myapp -n 50", "description": "Show last 50 sessions"},
                    {"command": "mic log acme/myapp --path src/", "description": "Sessions that touched src/"}
                ]
            },
            {
                "name": "blame",
                "category": "History",
                "description": "Show who changed each line (session attribution)",
                "usage": "mic blame <ORG/PROJECT> <PATH>",
                "args": [
                    {"name": "org/project", "description": "Project reference", "required": true},
                    {"name": "path", "description": "File path", "required": true}
                ],
                "options": [],
                "examples": [
                    {"command": "mic blame acme/myapp src/main.rs", "description": "Show line-by-line attribution"}
                ],
                "notes": "Shows which session last modified each line, along with the session goal."
            },
            {
                "name": "diff",
                "category": "History",
                "description": "Show changes between two positions",
                "usage": "mic diff <ORG/PROJECT> <FROM> [TO]",
                "args": [
                    {"name": "org/project", "description": "Project reference", "required": true},
                    {"name": "from", "description": "Starting position (e.g., @5)", "required": true},
                    {"name": "to", "description": "Ending position (defaults to HEAD)", "required": false}
                ],
                "options": [],
                "examples": [
                    {"command": "mic diff acme/myapp @5 @10", "description": "Changes from position 5 to 10"},
                    {"command": "mic diff acme/myapp @5", "description": "Changes from position 5 to HEAD"}
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
            {"name": "MIC_HOME", "description": "Override config directory", "default": "~/.mic"},
            {"name": "NO_COLOR", "description": "Disable colored output", "default": ""}
        ],
        
        "error_codes": [
            {"code": "not_authenticated", "message": "Not logged in", "resolution": "Run `mic auth login`"},
            {"code": "token_expired", "message": "Authentication token expired", "resolution": "Run `mic auth login` again"},
            {"code": "not_in_workspace", "message": "Not in a workspace directory", "resolution": "Run `mic checkout <org/project>` first, or specify project explicitly"},
            {"code": "no_active_session", "message": "No active session", "resolution": "Run `mic session start \"<goal>\"` first"},
            {"code": "session_already_active", "message": "A session is already active", "resolution": "Run `mic session land` or `mic session abandon` first"},
            {"code": "invalid_project_ref", "message": "Invalid project reference format", "resolution": "Use format: org/project (e.g., 'acme/myapp')"},
            {"code": "conflicts_detected", "message": "Conflicts with upstream changes", "resolution": "Run `mic session resolve` or `mic sync`"}
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
    fn test_parse_project_ref_valid() {
        assert_eq!(parse_project_ref("acme/myapp"), Some(("acme", "myapp")));
        assert_eq!(parse_project_ref("org/project"), Some(("org", "project")));
        assert_eq!(parse_project_ref("a/b"), Some(("a", "b")));
    }

    #[test]
    fn test_parse_project_ref_invalid() {
        assert_eq!(parse_project_ref("noslash"), None);
        assert_eq!(parse_project_ref("/project"), None);
        assert_eq!(parse_project_ref("org/"), None);
        assert_eq!(parse_project_ref(""), None);
        assert_eq!(parse_project_ref("/"), None);
    }

    #[test]
    fn test_looks_like_project_ref() {
        assert!(looks_like_project_ref("acme/myapp"));
        assert!(!looks_like_project_ref("just-a-goal"));
        assert!(!looks_like_project_ref("Fix the bug"));
    }
}
