# Micelio & mic

Micelio is a minimalist git forge, and mic is its CLI client.

## Installing mic

mic is built with Zig. To build from source:

```bash
# Clone the micelio repository
git clone https://github.com/ruby/micelio.git
cd micelio/cli

# Build the CLI
zig build

# The binary will be at zig-out/bin/mic
# Move it to your PATH
cp zig-out/bin/mic /usr/local/bin/
```

## Authentication

Before using most commands, authenticate with the forge:

```bash
# Login via device flow (opens browser)
mic auth login

# Check authentication status
mic auth status

# Remove stored credentials
mic auth logout
```

## Project Management

```bash
# List projects in an organization
mic project list <organization>

# Create a new project
mic project create <organization> <handle> <name> [--description <desc>]

# Get project details
mic project get <organization> <handle>

# Update project fields
mic project update <organization> <handle> [--name <name>] [--description <desc>] [--new-handle <handle>]

# Delete a project
mic project delete <organization> <handle>
```

## Working with Content

```bash
# List files in a project
mic ls <account> <project> [--path prefix]

# Print file contents
mic cat <account> <project> <path>
```

## Workspaces

Create a local workspace to work on a project:

```bash
# Checkout a project (creates local workspace)
mic checkout <account>/<project> [--path dir]

# Show workspace changes
mic status

# Land workspace changes
mic land <goal>

# Sync workspace with upstream changes
mic sync [--strategy ours|theirs|interactive]

# Write content from stdin to a file
mic write <path>
```

## Virtual filesystem

Mount a project via NFS for read-only browsing:

```bash
# Mount a project (serves via NFS)
mic mount <account>/<project> [--path dir] [--port 20490]

# Unmount a project
mic unmount <mount-path>
```

## Sessions

Sessions track work progress with notes and goals:

```bash
# Start a new session
mic session start <organization> <project> <goal>

# Show current session status
mic session status

# Add a note to the session
mic session note <message> [--role human|agent]

# Land the session (push to forge)
mic session land

# Abandon the current session
mic session abandon
```

## Quick Start

```bash
# 1. Authenticate
mic auth login

# 2. List available projects
mic project list micelio

# 3. Checkout a project
mic checkout micelio/myproject

# 4. Start a session
mic session start micelio myproject "Add feature X"

# 5. Make changes and add notes
echo "content" | mic write src/new_file.txt
mic session note "Added new file for feature X"

# 6. Land your changes
mic session land
```
