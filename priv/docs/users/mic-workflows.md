%{
  title: "mic Workflows",
  description: "Common mic workflows for daily use."
}
---

This guide covers the most common mic workflows for daily use.

## Install and authenticate

```bash
# Build from source
zig build

# Login via device flow
mic auth login

# Verify auth
mic auth status
```

## Create a project and checkout a workspace

```bash
# List projects in an org
mic project list <organization>

# Create a new project
mic project create <organization> <handle> <name> [--description <desc>]

# Checkout a project into a local workspace
mic checkout <account>/<project> [--path dir]
```

## Start a session and land changes

```bash
# Start a new session with a goal
mic session start <organization> <project> "Describe the goal"

# Inspect local changes
mic status

# Add a note about your progress
mic session note "Explain what changed" [--role human|agent]

# Land your changes
mic session land
```

## Update files in a workspace

```bash
# Write file contents from stdin
printf "Hello" | mic write README.md

# Sync workspace with upstream changes
mic sync [--strategy ours|theirs|interactive]
```

## Browse project content without checkout

```bash
# List files at the project root
mic ls <account> <project>

# Read a file at a specific path
mic cat <account> <project> <path>
```

## Mount a read-only filesystem

```bash
# Mount a project via NFS for browsing
mic mount <account>/<project> [--path dir] [--port 20490]

# Unmount when done
mic unmount <mount-path>
```

## Inspect history

```bash
# List landed sessions
mic log

# Diff two refs
mic diff <ref1> <ref2>
```
