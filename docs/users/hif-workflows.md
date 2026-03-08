# hif Workflows

This guide covers the most common `hif` workflows for daily use.

## Authenticate

```bash
# Login via device flow
hif auth login

# Verify auth
hif auth status
```

## Create a repository and checkout a workspace

```bash
# List repositories in an account
hif repository list <account>

# Create a new repository
hif repository create <account>/<repository> "<name>" [--description <desc>]

# Checkout a repository into a local workspace
hif checkout <account>/<repository> [--path dir]
```

## Link an existing local repository

Use this when you already have a local repository directory and want to land it
to a Micelio repository without running checkout.

```bash
# Link by repository ref (uses default server)
hif link <account>/<repository>

# Land your changes
hif land "Describe the goal"
```

## Start a session and land changes

```bash
# Start a new session with a goal
hif session start <account>/<repository> "Describe the goal"

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

## Browse repository content without checkout

```bash
# List files at the repository root
hif tree <account>/<repository>

# Read a file at a specific path
hif show <account>/<repository> <path>

# Search indexed repository content
hif grep <account>/<repository> "<query>"
```

## Mount a read-only filesystem

```bash
# Mount a repository via local mirror
hif mount <account>/<repository> [--path dir] [--port 20490]

# Unmount when done
hif unmount <mount-path>
```

## Inspect history

```bash
# List landed sessions
hif log <account>/<repository>

# Diff two refs
hif diff <account>/<repository> <from-ref> [to-ref]

# Show line attribution
hif blame <account>/<repository> <path>
```
