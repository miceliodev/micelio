%{
  title: "Getting Started",
  description: "Set up your development environment and make your first contribution."
}
---

This guide helps you set up your development environment and make your first contribution to Micelio.

## Prerequisites

We use [Nix](https://nixos.org/) to manage development dependencies. This ensures everyone has the same versions of Elixir, Zig, PostgreSQL, and other tools.

**Install Nix:**

```bash
# On macOS or Linux
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

We recommend the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer) as it enables flakes by default and provides an easy uninstall option.

**Install direnv (recommended):**

[direnv](https://direnv.net/) automatically loads the Nix environment when you enter the project directory.

```bash
# On macOS
brew install direnv

# On Linux (Ubuntu/Debian)
sudo apt install direnv
```

Add to your shell config (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
eval "$(direnv hook bash)"  # or zsh, fish, etc.
```

## Setup

```bash
# Clone the project
git clone https://github.com/micelio/micelio.git
cd micelio

# Allow direnv to load the environment (first time only)
direnv allow

# Or manually enter the Nix shell
nix develop

# Install Elixir dependencies
mix deps.get

# Setup database
mix ecto.setup

# Build Zig CLI
cd mic && zig build && cd ..

# Start development server
mix phx.server
```

The first time you run `nix develop` or enter the directory with direnv, Nix will download and set up all the required tools. This may take a few minutes.

## Verify Installation

```bash
# Run all tests
mix test
cd mic && zig build test
```

## What Nix Provides

The Nix flake includes:

- **Elixir 1.17** with Erlang/OTP 27
- **Zig 0.13**
- **PostgreSQL 16**
- **libgit2** (for Zig NIFs)
- **Rust toolchain** (for makeup_syntect syntax highlighting)
- Development tools: git, gh CLI

## Development Commands

### Elixir (Forge)

| Command | Purpose |
|---------|---------|
| `mix compile --warnings-as-errors` | Compile with strict warnings |
| `mix phx.server` | Start dev server |
| `mix test` | Run tests |
| `mix test --failed` | Re-run failed tests |
| `mix format` | Format code |
| `mix format --check-formatted` | Check formatting |
| `mix ecto.migrate` | Run migrations |
| `mix precommit` | Run all pre-commit checks |

### Zig (mic CLI)

| Command | Purpose |
|---------|---------|
| `zig build` | Build |
| `zig build test` | Run tests |
| `zig fmt src/` | Format code |
| `zig fmt --check src/` | Check formatting |

## Pre-commit Checklist

Before pushing changes, run:

```bash
mix precommit
```

This runs compilation with warnings as errors, formatting checks, and tests.

## Making Changes

1. Create a branch for your changes
2. Make your changes following the code style guidelines
3. Run `mix precommit` to verify everything passes
4. Submit a pull request with a clear description

## Troubleshooting

### direnv not loading automatically

Make sure you've added the direnv hook to your shell config and restarted your terminal. Then run:

```bash
direnv allow
```

### Nix command not found

Restart your terminal after installing Nix, or source your shell profile:

```bash
source ~/.bashrc  # or ~/.zshrc
```

### PostgreSQL connection issues

The Nix environment sets up PostgreSQL to use a local socket. If you have issues, check that your `config/dev.exs` uses the correct socket path, or set `PGHOST` environment variable.
