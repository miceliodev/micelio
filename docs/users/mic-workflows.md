# hif Workflows

This guide covers the most common `hif` workflows for daily use.

## Install and authenticate

```bash
# Build from source
cd hif && cargo build --release

# Login via device flow
hif auth login

# Verify auth
hif auth status
```

## Create a project and checkout a workspace

```bash
# List projects in an org
hif project list <organization>

# Create a new project
hif project create <organization>/<project> "<name>" [--description <desc>]

# Checkout a project into a local workspace
hif checkout <organization>/<project> [--path dir]
```

## Link an existing local project

Use this when you already have a local project directory and want to land it
to a Micelio project without running checkout.

```bash
# Link by project ref (uses default server)
hif link <organization>/<project>

# Land your changes
hif land "Describe the goal"
```

## Start a session and land changes

```bash
# Start a new session with a goal
hif session start <organization>/<project> "Describe the goal"

# Inspect local changes
hif status

# Add a note about your progress
hif session note "Explain what changed" [--role human|agent]

# Land your changes
hif session land
```

## Sync workspace with upstream changes

```bash
hif sync [--strategy ours|theirs|interactive]
```

## Browse project content without checkout

```bash
# List files at the project root
hif tree <organization>/<project>

# Read a file at a specific path
hif show <organization>/<project> <path>

# Search indexed repository content
hif grep <organization>/<project> "<query>"
```

## Mount a read-only filesystem

```bash
# Mount a project via local mirror
hif mount <organization>/<project> [--path dir] [--port 20490]

# Unmount when done
hif unmount <mount-path>
```

## Inspect history

```bash
# List landed sessions
hif log <organization>/<project>

# Diff two refs
hif diff <organization>/<project> <from-ref> [to-ref]

# Show line attribution
hif blame <organization>/<project> <path>
```
