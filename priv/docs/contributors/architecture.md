%{
  title: "Architecture",
  description: "Overview of Micelio's technical architecture and design decisions."
}
---

Micelio is a monorepo containing two main components:

- **Forge** (Elixir/Phoenix) - The web application and gRPC server
- **mic** (Zig) - The command-line interface

## Tech Stack

| Component | Technology | Location |
|-----------|------------|----------|
| Web App | Elixir/Phoenix 1.8 | `/` (root) |
| CLI | Zig 0.15 | `/mic` |
| Database | PostgreSQL + Ecto | - |
| Frontend | LiveView + vanilla CSS | - |

## Key Modules

### mic (Zig CLI)

Located in `mic/`, organized as:

- `mic/src/core/hash.zig` - Blake3 hashing for content-addressed storage
- `mic/src/core/bloom.zig` - Bloom filters for conflict detection
- `mic/src/core/hlc.zig` - Hybrid Logical Clocks for distributed timestamps
- `mic/src/core/tree.zig` - B+ tree for directory structures
- `mic/src/root.zig` - Library entry point and re-exports

### Zig NIFs

Git operations are implemented using Zig NIFs with libgit2 in `zig/git/git.zig`:

- **Shared utilities** - `init_libgit2()`, `null_terminate()`
- **Status domain** - `status()` for working tree status
- **Repository domain** - `repository_init()`, `repository_default_branch()`
- **Tree domain** - `tree_list()`, `tree_blob()` for browsing repository content

The Elixir module `Micelio.Git` exposes:

- `status/1` - Get working tree status
- `repository_init/1` - Initialize a new repository
- `repository_default_branch/1` - Get the default branch name
- `tree_list/3` - List entries at a ref and path
- `tree_blob/3` - Read file content at a ref and path

All functions return `{:ok, result}` or `{:error, reason}` tuples.

## Design Principles

### Forge-First Architecture

The server is the source of truth, not the local disk. This enables:
- Stateless agents that can work from anywhere
- S3 as primary storage (like Turbopuffer)
- O(log n) operations via bloom filters
- Coordinator-free landing via S3 conditional writes

### Code Quality Standards

- **Single Responsibility**: Each module/function does ONE thing well
- **Clear boundaries**: Separate concerns (parsing, validation, business logic, I/O)
- **Explicit over implicit**: No magic; make data flow obvious
- **Fail fast**: Validate inputs at boundaries, return errors early
