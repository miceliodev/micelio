# Micelio for AI Agents

Micelio is a forge platform built with Elixir/Phoenix, Rust for CLI (`mic`), Zig for NIFs, and vanilla CSS for web UI.

## IMPORTANT: Terminology

**Always use "repositories" for code containers.** Micelio uses the term "repositories" consistently throughout the codebase, documentation, and UI.

## IMPORTANT: Internationalization (i18n)

**All user-facing strings must use gettext.** When adding or modifying UI text:

1. Wrap strings with `gettext("...")` in templates and modules
2. Run `mix gettext.extract` to extract new strings to POT files
3. Run `mix gettext.merge priv/gettext` to update all locale PO files
4. Ensure translations are provided for all supported locales: English (en), Korean (ko), Simplified Chinese (zh_CN), Traditional Chinese (zh_TW), Japanese (ja)

Translation files are located in `priv/gettext/{locale}/LC_MESSAGES/`.

## IMPORTANT: Icons

Use open source icons from https://icones.js.org/ and embed them as inline SVG in templates. Prefer a single icon set (e.g., Tabler) for consistency.

## IMPORTANT: Repository Interactions

When adding new user interactions that should influence "recent repositories", add them to the repository interaction tracking in the Repositories context and update the relevant controllers/live views to record them.

## IMPORTANT: Session Workflow

When working on code changes, use Micelio sessions:

```bash
mic session start <org> <repository> "goal"
mic session note "progress update"
mic session land
```

Use sessions for all changes unless the user explicitly requests otherwise.

## IMPORTANT: CLI Design for Agents

**The `mic` CLI must be self-documenting for AI agents.** Agents should be able to learn how to use the CLI just from help output, without needing separate documentation files.

Design principles:
1. **Rich help with examples**: Every command includes `after_help` with EXAMPLES, WORKFLOW, and NOTES sections
2. **Main help has quick start**: The root `--help` shows a complete workflow from auth to landing
3. **`--help --json` for agents**: Machine-readable help that agents can parse programmatically
4. **Actionable error messages**: Errors should suggest next steps (e.g., "Run 'mic auth login' first")

The `--help --json` output includes:
- `concepts`: Definitions of Session, Workspace, Forge, Landing, Position
- `workflow`: Numbered steps for the typical flow
- `commands`: Full command tree with args, options, and requirements (`requires_auth`, `requires_workspace`, `requires_session`)
- `error_codes`: What each error means and how to fix it

When adding new commands:
1. Add `after_help` with examples
2. Update `generate_help_json()` in `mic/src/cli.rs`
3. Include `requires_auth`, `requires_workspace`, `requires_session` metadata
4. Add error recovery guidance to `error_codes`

## Blog Post Translations

Blog posts are organized by locale in the filesystem:
- `priv/posts/en/2026/01-14-post-id.md` (English, default)
- `priv/posts/ja/2026/01-14-post-id.md` (Japanese translation)
- etc.

When translating a blog post:
1. Create the locale directory if it doesn't exist: `priv/posts/{locale}/`
2. Copy the original post maintaining the same directory structure (year/filename)
3. Translate the content while keeping the same frontmatter structure
4. The post ID (derived from filename) must match across locales for fallback to work

If a translation is not available for a locale, the English version is used as fallback.

---

## Project Context

Micelio is a monorepo containing:

- **Forge** (Elixir/Phoenix) - The web application and gRPC server
- **mic** (Rust) - The `mic` command-line interface

### Tech Stack

| Component | Technology | Location |
|-----------|------------|----------|
| Web App | Elixir/Phoenix 1.8 | `/` (root) |
| CLI | Rust | `/mic` |
| Database | PostgreSQL + Ecto | - |
| Frontend | LiveView + vanilla CSS | - |

### Key Modules

#### mic (Rust CLI)

Located in `mic/`, organized as:

- `mic/src/core/hash.rs` - Blake3 hashing for content-addressed storage
- `mic/src/core/bloom.rs` - Bloom filters for conflict detection
- `mic/src/core/hlc.rs` - Hybrid Logical Clocks for distributed timestamps
- `mic/src/core/tree.rs` - B+ tree for directory structures
- `mic/src/main.rs` - CLI entry point
- `mic/src/cli.rs` - Command definitions (clap)
- `mic/src/grpc/` - gRPC client for forge communication
- `mic/src/workspace/` - Local workspace management
- `mic/src/commands/` - Command implementations

#### Zig NIFs

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

See [docs/contributors/next.md](./docs/contributors/next.md) for upcoming features and [docs/contributors/design.md](./docs/contributors/design.md) for architecture.

---

## Architecture: mic is NOT Git

**mic is an alternative to Git, not a wrapper around it.** It uses a completely different model:

| Aspect | Git | mic + Micelio |
|--------|-----|---------------|
| **Unit of work** | Commit (snapshot) | Session (goal + context + changes) |
| **Storage model** | Distributed (.git folder) | Forge-first (S3 is source of truth) |
| **Sync protocol** | upload-pack/receive-pack | gRPC + S3 CAS |
| **History** | DAG of commits | Append-only log of landing positions |
| **Conflict detection** | 3-way merge | Bloom filters (O(log n)) |

### Sessions (Not Commits)

Every unit of work is a **session** containing:
- **Goal** - what you're trying to accomplish
- **Conversation** - discussion between agents and humans
- **Decisions** - why things were done a certain way
- **Changes** - the actual file modifications

### CLI to Forge Communication

mic CLI communicates with Micelio via **gRPC** (not HTTP REST, not Git protocol):

- `micelio.auth.v1.AuthService` - Device flow login
- `micelio.repositories.v1.RepositoryService` - Repository CRUD
- `micelio.sessions.v1.SessionService` - Start/land/manage sessions
- `micelio.content.v1.ContentService` - Read files, list trees, blame

### Landing (Pushing Changes)

Landing uses **compare-and-swap (CAS)** on S3's HEAD object:

1. Read current HEAD + ETag
2. Check conflicts with bloom filters
3. Build new tree hash
4. Atomic CAS write to HEAD (S3 if-match)
5. Write landing record to append-only log
6. Store conflict index for future checks

No coordinator needed - S3 provides atomicity.

### Storage Layout (S3)

```
repositories/{repository_id}/
├── head                    # Current position + tree hash (48 bytes)
├── landing/{position}.bin  # Append-only landing records
├── sessions/{id}.bin       # Session summaries
├── trees/{hash}.bin        # B+ tree snapshots
└── blobs/{hash}.bin        # File content (zstd compressed)
```

### mic CLI Commands

```bash
# Authentication
mic auth login              # Device flow auth
mic auth status             # Check auth status

# Repositories
mic repo create <org> <handle> <name>
mic repo list <org>

# Working with content (no checkout needed)
mic cat <org> <repository> <path>      # Read file
mic ls <org> <repository>              # List directory
mic log <org/repository>               # List sessions
mic blame <org> <repository> <path>    # Session attribution

# Local workspace
mic checkout <org/repository>          # Create local workspace
mic status                             # Show workspace changes
mic write <path>                       # Stage file (reads from stdin)
mic land "goal"                        # Quick land

# Sessions (explicit workflow)
mic session start <org> <repository> "goal"
mic session note "message"             # Add conversation entry
mic session land                       # Push to forge
mic session abandon                    # Discard session

# Sync
mic sync                               # Pull latest from forge
```

### Importing from Git

Micelio can import from Git forges (GitHub, GitLab, etc.) via the web UI import feature. This:
1. Clones the Git repo
2. Stores a bundle in S3
3. Creates a session with all files
4. Lands the session as position 1

---

## First Run Setup

### Prerequisites

Install the following dependencies:

- [Elixir](https://elixir-lang.org/install.html) (1.18+)
- [PostgreSQL](https://www.postgresql.org/download/)
- [Rust](https://rustup.rs/) (1.75+)
- [Zig](https://ziglang.org/download/) (0.15+ for NIFs)

### Setup

```bash
# Install Elixir dependencies
mix deps.get

# Setup database
mix ecto.setup

# Build Rust CLI
cd mic && cargo build --release && cd ..

# Start development server
mix phx.server
```

### Verify Installation

```bash
# Run all tests
mix test
cd mic && cargo test
```

### Important Files

| File | Purpose |
|------|---------|
| `AGENTS.md` | This guide (root hub) |
| `priv/static/skill.md` | Agent guide served at `/skill.md` - keep in sync with AGENTS.md |
| `priv/static/SKILL.md` | mic CLI docs served at `/SKILL.md` |

---

## Every Session Checklist

Before making changes:

1. **Pull latest**: `git pull origin main`
2. **Check tests pass**: `mix test`
3. **Review recent commits**: `git log --oneline -10`

### Quick Reference

```bash
# Build
mix compile --warnings-as-errors
cd mic && cargo build --release

# Test
mix test
cd mic && cargo test

# Format
mix format --check-formatted
cd mic && cargo fmt --check

# Pre-commit (run before pushing)
mix compile --warnings-as-errors && mix format --check-formatted && mix test
cd mic && cargo build --release && cargo fmt --check && cargo test
```

### Shortcut

Use the precommit alias when done with all changes:

```bash
mix precommit
```

---

## Tools & Commands

### Elixir (Forge)

| Command | Purpose |
|---------|---------|
| `mix compile --warnings-as-errors` | Compile with strict warnings |
| `mix phx.server` | Start dev server |
| `mix test` | Run tests |
| `mix test --failed` | Re-run failed tests |
| `mix test test/path.exs` | Run specific test file |
| `mix format` | Format code |
| `mix format --check-formatted` | Check formatting |
| `mix ecto.migrate` | Run migrations |
| `mix ecto.gen.migration name` | Generate migration |
| `mix help task_name` | Get task docs |
| `mix precommit` | Run all pre-commit checks |

### Rust (mic CLI)

| Command | Purpose |
|---------|---------|
| `cargo build --release` | Build release binary |
| `cargo build` | Build debug binary |
| `cargo test` | Run tests |
| `cargo fmt` | Format code |
| `cargo fmt --check` | Check formatting |
| `cargo clippy` | Run linter |

### Static Assets

| File | Served At | Purpose |
|------|-----------|---------|
| `priv/static/SKILL.md` | `/SKILL.md` | mic CLI documentation |
| `priv/static/skill.md` | `/skill.md` | Agent guide (keep aligned with AGENTS.md) |

### HTTP Requests

Use `:req` (`Req`) for HTTP requests. It's included by default.

**Never use**: `:httpoison`, `:tesla`, `:httpc`

---

## Skills & Static Assets

When making changes to CLI commands or agent capabilities, update the corresponding static files:

- **SKILL.md** (`priv/static/SKILL.md`) - Documentation for the mic CLI served at `/SKILL.md`
- **skill.md** (`priv/static/skill.md`) - Agent guide served at `/skill.md`, keep aligned with `AGENTS.md`

When you update `AGENTS.md`, also update `priv/static/skill.md` so `/skill.md` stays in sync.

---

## Memory & Continuity

### Project State

Key places to check for project state:

- `docs/contributors/next.md` - Upcoming features and roadmap
- `docs/contributors/design.md` - Architecture decisions
- Recent git commits: `git log --oneline -20`

### Session Notes

If you need to pass context to a future session, document it in the PR description or commit messages.

---

## Development Workflow

### Deployment

The app is deployed using [Kamal](https://kamal-deploy.org/) via **Continuous Integration**.

**Workflow:**
1. Push changes directly to `main` branch
2. GitHub Actions CI automatically deploys
3. No manual deployment needed

**Manual deployment (if needed):**
```bash
source .env && kamal deploy
```

### Code Quality Standards

Write code as if it will be maintained for 10 years by engineers who've never seen it before.

#### Architecture Principles

- **Single Responsibility**: Each module/function does ONE thing well
- **Clear boundaries**: Separate concerns (parsing, validation, business logic, I/O)
- **Explicit over implicit**: No magic; make data flow obvious
- **Fail fast**: Validate inputs at boundaries, return errors early

#### Zig-Specific

- **Memory safety is paramount**:
  - Always pair allocations with deallocations (`defer allocator.free(...)`)
  - Use arena allocators for request-scoped memory
  - Prefer stack allocation when size is bounded
  - Document ownership: who allocates, who frees
- **No leaks**: Run `zig build test` with `--detect-leaks` when available
- **Error handling**: Return errors, don't panic. Use `errdefer` for cleanup
- **Slices over pointers**: Prefer `[]const u8` over `[*]const u8`

#### Elixir-Specific

- **Let it crash**: Use supervisors, don't over-handle errors
- **Pattern match at function heads**: Not nested case statements
- **Pipelines for data transformation**: Keep them readable (3-5 steps max)
- **Contexts for boundaries**: Business logic in contexts, not controllers/LiveViews

#### Code Organization

- **Consistent naming**: `verb_noun` for functions, `Noun` for modules
- **Small functions**: If it scrolls, split it
- **Comments explain WHY, not WHAT**: Code should be self-documenting
- **Group related functions**: Public API at top, private helpers below

---

## Debugging Production Issues

When encountering 500 errors or unexpected behavior in production:

### 1. Check the Logs

```bash
# View live logs
kamal logs

# Follow logs in real-time
kamal logs -f
```

### 2. Identify the Error Pattern

Look for:
- **500 errors**: Check the exact controller and function that failed
- **Pattern**: Is it happening on specific pages?
- **Error messages**: Look for Elixir stacktraces

### 3. Reproduce Locally

```bash
mix phx.server
# Navigate to the problematic page
# Check local logs for similar errors
```

### 4. Common Production Issues

| Issue | Cause |
|-------|-------|
| Missing assigns | Production compiles with `phoenix_gen_html` which exposes template errors |
| Environment-specific | Code only fails in production |
| Database issues | Missing migrations or data |
| Asset compilation | CSS/JS not properly compiled |

### 5. Common 500 Error Causes

- Accessing `@changeset` directly in template instead of `@form`
- Missing required assign in LiveView (e.g., `@page_title`, `@current_user`)
- Pattern match failures in `handle_params`
- Database connection issues
- Template syntax errors
- Missing CSS imports

### 6. Fix Workflow

```bash
# 1. Make fix locally
# 2. Run tests
mix test
# 3. Format
mix format
# 4. Check warnings
mix compile --warnings-as-errors
# 5. Commit and push
git add . && git commit -m "fix: description" && git push
# 6. Verify CI passes
# 7. Check logs
kamal logs
```

### 7. Useful Commands

```bash
# Check production logs
kamal logs

# SSH into production container
kamal ssh

# Check deployment status
kamal status

# Check app health
kamal healthcheck

# Deploy to production
kamal deploy

# Rollback to previous version
kamal rollback
```

### Remember

- Production is stricter than development
- `mix compile --warnings-as-errors` catches issues that work in dev
- Always check logs first - they contain the stacktrace

---

## Writing Tests

### General Principles

- **Test behavior, not implementation**: Focus on public API contracts
- **Edge cases**: Empty inputs, nil/null, boundaries, unicode, large inputs
- **Memory tests for Zig**: Ensure no leaks under various code paths
- **Property-based tests** where applicable (StreamData for Elixir)
- **Do not modify OS environment variables in tests**: Use dependency injection via config/env maps instead
- **Do not modify application environment in tests**: Avoid `Application.put_env/3` and `Application.delete_env/2`; inject via opts/config args instead
- **Do not use Process dictionary for dependency injection**: Avoid `Process.put/2` and `Process.get/1` to pass instances

### Elixir Tests

```bash
mix test                    # Run all tests
mix test --failed           # Re-run failed tests
mix test test/path.exs      # Run specific file
```

#### Test Module Setup

```elixir
defmodule MyApp.MyTest do
  use ExUnit.Case, async: true  # Always use async: true

  # Always use start_supervised! for processes
  setup do
    pid = start_supervised!(MyGenServer)
    %{pid: pid}
  end
end
```

#### Process Synchronization

**Avoid** `Process.sleep/1` and `Process.alive?/1`.

Instead of sleeping to wait for a process:

```elixir
# Good - use monitor
ref = Process.monitor(pid)
assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

# Good - use :sys.get_state for sync
_ = :sys.get_state(pid)
```

### Zig Tests

```bash
cd mic && zig build test
```

Tests are organized by module. Each core module includes comprehensive unit tests covering normal operation, edge cases, and error conditions.

### LiveView Tests

Use `Phoenix.LiveViewTest` module and `LazyHTML` for assertions.

#### Key Points

- Form tests use `render_submit/2` and `render_change/2`
- **Always** reference key element IDs in tests
- Use `element/2`, `has_element/2` instead of raw HTML matching
- Test outcomes, not implementation details

#### Debugging Test Failures

```elixir
html = render(view)
document = LazyHTML.from_fragment(html)
matches = LazyHTML.filter(document, "your-selector")
IO.inspect(matches, label: "Matches")
```

---

## Code Style & Conventions

### Elixir

#### Syntax

- Lists **do not support index access**: Use `Enum.at/2`, pattern matching, or `List` functions
- Variables are immutable but can be rebound; block expressions (`if`, `case`, `cond`) must bind results:

```elixir
# Wrong
if connected?(socket) do
  socket = assign(socket, :val, val)
end

# Right
socket =
  if connected?(socket) do
    assign(socket, :val, val)
  else
    socket
  end
```

- **Never** nest multiple modules in the same file
- **Never** use map access (`changeset[:field]`) on structs; use `struct.field` or `Ecto.Changeset.get_field/2`
- Use standard library for dates: `Time`, `Date`, `DateTime`, `Calendar`
- Don't use `String.to_atom/1` on user input
- Predicate functions end with `?` (not `is_`)
- Place `require`, `import`, and `use` at module level, never inside functions
- Use `Task.async_stream/3` with `timeout: :infinity` for concurrent enumeration

#### Mix

- Read docs with `mix help task_name` before using tasks
- **Avoid** `mix deps.clean --all` unless necessary

### Ecto

- **Never** use `@type` annotations in Ecto schema modules
- **Never** use section divider comments like `# ====` in context modules
- **Always** preload associations when accessed in templates
- `Ecto.Schema` fields use `:string` type even for `:text` columns
- `validate_number/2` does not support `:allow_nil`
- Fields set programmatically (like `user_id`) must not be in `cast` calls
- **Always** use `mix ecto.gen.migration name` for migrations

### Phoenix

- Router `scope` blocks include an optional alias prefixed for all routes
- Don't create aliases for route definitions; scope provides them
- Don't use `Phoenix.View`

### HEEx Templates

- **Always** use `~H` or `.html.heex` files
- Use `Phoenix.Component.form/1` and `to_form/2`, not `Phoenix.HTML.form_for`
- Add unique DOM IDs to key elements for testing
- **Never** use `else if` or `elsif`; use `cond` or `case`
- For literal curly braces in code blocks, use `phx-no-curly-interpolation`:

```heex
<code phx-no-curly-interpolation>
  let obj = {key: "val"}
</code>
```

- Class attributes support lists with conditionals:

```heex
<a class={[
  "px-2 text-white",
  @flag && "py-5",
  if(@condition, do: "border-red", else: "border-blue")
]}>
```

- **Never** use `<% Enum.each %>`; use `<%= for item <- @collection do %>`
- Use `<%!-- comment --%>` for HEEx comments
- Use `{...}` for attribute interpolation, `<%= %>` only within tag bodies

### LiveView

- Use `<.link navigate={}>` and `<.link patch={}>`, not deprecated `live_redirect`/`live_patch`
- **Avoid** LiveComponents unless specifically needed
- Name LiveViews with `Live` suffix: `AppWeb.WeatherLive`

#### Streams

**Always** use streams for collections:

```elixir
stream(socket, :messages, [msg])           # append
stream(socket, :messages, [msg], at: -1)   # prepend
stream(socket, :messages, msgs, reset: true) # reset
stream_delete(socket, :messages, msg)      # delete
```

Template:

```heex
<div id="messages" phx-update="stream">
  <div :for={{id, msg} <- @streams.messages} id={id}>
    {msg.text}
  </div>
</div>
```

Streams are not enumerable. To filter, refetch and reset:

```elixir
messages = list_messages(filter)
stream(socket, :messages, messages, reset: true)
```

#### Forms

```elixir
# In LiveView
socket = assign(socket, form: to_form(changeset))

# In template
<.form for={@form} id="my-form" phx-submit="save">
  <.input field={@form[:field]} type="text" />
</.form>
```

**Never** access `@changeset` in templates; always use `@form`.

#### JavaScript Interop

For `phx-hook`, always set `phx-update="ignore"` if the hook manages its own DOM, and provide a unique DOM ID.

**Colocated hooks** (names start with `.`):

```heex
<input id="phone" phx-hook=".PhoneNumber" />
<script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
  export default {
    mounted() { /* ... */ }
  }
</script>
```

**External hooks** go in `assets/js/` and are passed to `LiveSocket`.

### CSS

- **Never** use Tailwind CSS classes
- Use vanilla modern CSS only
- Design inspiration: GitHub Primer design system
- **No emojis** in UI or content

#### Design System Overview

Micelio uses a GitHub Primer-inspired design system with these core principles:

1. **Clarity over decoration**: Minimal visual noise, clear hierarchy
2. **Consistency**: Reuse patterns and components across pages
3. **Accessibility**: Sufficient contrast, focus states, semantic HTML
4. **Dark mode support**: All colors work in both light and dark themes

#### Design Tokens

All styling uses CSS variables in `assets/css/theme/tokens.css`:

```css
/* Naming convention */
--theme-ui-<category>-<value>

/* Examples */
--theme-ui-colors-primary      /* Colors */
--theme-ui-space-2             /* Spacing (8px grid) */
--theme-ui-fonts-body          /* Typography */
--theme-ui-radii-default       /* Border radius */
```

#### Color Palette

| Variable | Light Mode | Dark Mode | Usage |
|----------|-----------|-----------|-------|
| `--theme-ui-colors-text` | #1f2328 | #f0f6fc | Primary text |
| `--theme-ui-colors-background` | #ffffff | #0d1117 | Page background |
| `--theme-ui-colors-primary` | #0969da | #4493f8 | Links, accents |
| `--theme-ui-colors-muted` | #59636e | #9198a1 | Secondary text |
| `--theme-ui-colors-border` | #d1d9e0 | #3d444d | Borders |
| `--theme-ui-colors-surface` | #f6f8fa | #151b23 | Cards, navbar |
| `--theme-ui-colors-danger` | #d1242f | #f85149 | Errors, destructive |
| `--theme-ui-colors-success` | #1a7f37 | #3fb950 | Success states |

#### Typography Scale

| Element | Size Variable | Actual Size | Weight | Usage |
|---------|---------------|-------------|--------|-------|
| h1 | `font-size-2xl` | 28px | 700 (bold) | Page titles |
| h2 | `font-size-xl` | 24px | 600 (semibold) | Section headers |
| h3 | `font-size-lg` | 20px | 600 | Subsections |
| h4 | `font-size-md` | 16px | 600 | Card titles, minor headers |
| body | `font-size-base` | 15px | 400 | All body text |
| small/label | `font-size-sm` | 14px | 400-500 | Labels, secondary text |
| caption | `font-size-xs` | 12px | 400 | Hints, timestamps |

#### Typography Rules (MUST follow)

**Micelio uses system sans-serif throughout for a clean, technical feel:**

| Font | Variable | When to Use |
|------|----------|-------------|
| **System sans-serif** | `--theme-ui-fonts-heading` | Page titles, section headers, card titles, any "title" text |
| **System sans-serif** | `--theme-ui-fonts-body` | Body text, labels, descriptions, navigation, buttons |
| **Monospace** | `--theme-ui-fonts-mono` | Code, CLI commands, technical values |

##### Heading Font (System sans-serif) - Use for:

- `<h1>` through `<h6>` elements (automatic)
- Card titles (`.card-title`, `.repository-card-name`)
- List item titles (`.session-goal`, `.docs-category-title`)
- Step/item titles in instructional content
- Any text that names or identifies something

```css
/* ✓ CORRECT: Title uses heading font */
.card-title {
  font-family: var(--theme-ui-fonts-heading);
  font-size: var(--theme-ui-font-size-md);
  font-weight: var(--theme-ui-font-weights-semibold);
}

/* ❌ WRONG: Title using body font (inherits sans-serif) */
.card-title {
  font-weight: bold;  /* Missing font-family! */
}
```

##### Body Font (System) - Use for:

- Paragraphs and descriptions
- Navigation links
- Button text
- Form labels and inputs
- Table content
- Metadata (dates, counts, status)

```css
/* Body font is the default, no need to specify */
.description {
  color: var(--theme-ui-colors-muted);
}
```

##### Common Mistakes to Avoid

```css
/* ❌ WRONG: Using <strong> for a title without heading font */
<strong>Step Title</strong>

/* ✓ CORRECT: Style the strong as a title */
.step-header strong {
  font-family: var(--theme-ui-fonts-heading);
  font-weight: var(--theme-ui-font-weights-semibold);
}

/* ❌ WRONG: Mixing fonts inconsistently */
.card-a .title { font-family: var(--theme-ui-fonts-heading); }
.card-b .title { /* no font-family, uses body */ }

/* ✓ CORRECT: All titles use heading font */
.card .title {
  font-family: var(--theme-ui-fonts-heading);
}
```

##### Quick Reference: "Is this a title?"

Ask yourself: **"Does this text name or identify something?"**

| Text | Is it a title? | Font |
|------|----------------|------|
| "mic 0.1.0" | Yes (product name) | Heading |
| "Quick Start" | Yes (section name) | Heading |
| "Authenticate" | Yes (step name) | Heading |
| "Opens browser for OAuth..." | No (description) | Body |
| "Create Project" (button) | No (action) | Body |
| "3 sessions" | No (metadata) | Body |
| "test-project" | Depends on context | Mono if code, Heading if name |

#### Spacing Scale (8px grid)

| Variable | Value | Usage |
|----------|-------|-------|
| `--theme-ui-space-0` | 4px | Tight spacing |
| `--theme-ui-space-1` | 8px | Default gap |
| `--theme-ui-space-2` | 16px | Section padding |
| `--theme-ui-space-3` | 24px | Large gaps |
| `--theme-ui-space-4` | 32px | Page margins |

#### Layout & Spacing Model

**This model ensures consistent vertical rhythm and spacing across all pages.**

##### Page Structure

Every page follows this vertical structure:

```
┌─────────────────────────────────────────┐
│ .page-content (padding: space-2)        │
│ ┌─────────────────────────────────────┐ │
│ │ PAGE HEADER                         │ │
│ │ (margin-bottom: space-3)            │ │
│ │ (padding-bottom: space-2)           │ │
│ │ (border-bottom)                     │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ SECTION 1                           │ │
│ │ (margin-bottom: space-4)            │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ SECTION 2                           │ │
│ │ (margin-bottom: space-4)            │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

##### Spacing Rules (MUST follow)

| Context | Spacing | Variable | Example |
|---------|---------|----------|---------|
| **Between page sections** | 32px | `space-4` | Between "Recent Sessions" and "Files" sections |
| **After page header** | 24px | `space-3` | Below `.page-header` border |
| **Inside cards/containers** | 16px | `space-2` | Padding inside `.card`, `.repository-card` |
| **Between list items** | 16px | `space-2` | Gap in session lists, project lists |
| **Between form fields** | 16px | `space-2` | Gap between label+input groups |
| **Between related elements** | 8px | `space-1` | Between label and input, title and subtitle |
| **Tight groupings** | 4px | `space-0` | Icon and text, badge clusters |

##### Section Anatomy

Each section within a page:

```css
.section {
  margin-bottom: var(--theme-ui-space-4);  /* 32px - separation from next section */
}

.section-header {
  margin-bottom: var(--theme-ui-space-2);  /* 16px - space before content */
}

.section-title {
  /* No margin-top (handled by section spacing) */
  margin-bottom: var(--theme-ui-space-1);  /* 8px - tight to subtitle/description */
}

.section-content {
  /* Lists, cards, forms go here */
}
```

##### Component Spacing Patterns

**Cards in a list:**
```css
.card-list {
  display: flex;
  flex-direction: column;
  gap: var(--theme-ui-space-2);  /* 16px between cards */
}
```

**Card internal spacing:**
```css
.card {
  padding: var(--theme-ui-space-2);  /* 16px padding */
}

.card-title {
  margin-bottom: var(--theme-ui-space-1);  /* 8px to description */
}

.card-description {
  margin-bottom: var(--theme-ui-space-1);  /* 8px to meta */
}

.card-meta {
  margin-top: var(--theme-ui-space-2);  /* 16px - visual separation */
}
```

**Form spacing:**
```css
.form {
  display: flex;
  flex-direction: column;
  gap: var(--theme-ui-space-2);  /* 16px between field groups */
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: var(--theme-ui-space-1);  /* 8px between label and input */
}

.form-actions {
  margin-top: var(--theme-ui-space-3);  /* 24px - emphasize actions */
  display: flex;
  gap: var(--theme-ui-space-1);  /* 8px between buttons */
}
```

##### Grid Layouts

**Two-column layouts:**
```css
.two-column {
  display: grid;
  grid-template-columns: 2fr 1fr;  /* Main content + sidebar */
  gap: var(--theme-ui-space-3);    /* 24px between columns */
}

@media (max-width: 60rem) {
  .two-column {
    grid-template-columns: 1fr;    /* Stack on mobile */
    gap: var(--theme-ui-space-4);  /* 32px when stacked */
  }
}
```

**Card grids:**
```css
.card-grid {
  display: grid;
  gap: var(--theme-ui-space-2);  /* 16px between cards */
}

@media (min-width: 60rem) {
  .card-grid {
    grid-template-columns: repeat(2, 1fr);  /* 2 columns on desktop */
  }
}
```

##### Anti-patterns (NEVER do)

```css
/* ❌ WRONG: Arbitrary pixel values */
.bad { margin-bottom: 20px; }

/* ✓ CORRECT: Use spacing variables */
.good { margin-bottom: var(--theme-ui-space-2); }

/* ❌ WRONG: Inconsistent section spacing */
.section-a { margin-bottom: var(--theme-ui-space-2); }
.section-b { margin-bottom: var(--theme-ui-space-3); }

/* ✓ CORRECT: All sections use space-4 */
.section-a { margin-bottom: var(--theme-ui-space-4); }
.section-b { margin-bottom: var(--theme-ui-space-4); }

/* ❌ WRONG: Both margin-top and margin-bottom on same element */
.bad { margin-top: var(--theme-ui-space-2); margin-bottom: var(--theme-ui-space-2); }

/* ✓ CORRECT: Use margin-bottom only (except for first-child resets) */
.good { margin-bottom: var(--theme-ui-space-2); }

/* ❌ WRONG: Padding for spacing between siblings */
.item { padding-bottom: var(--theme-ui-space-2); }

/* ✓ CORRECT: Use gap on parent container */
.list { display: flex; flex-direction: column; gap: var(--theme-ui-space-2); }
```

##### Quick Reference

| What you're spacing | Use this |
|---------------------|----------|
| Page sections | `margin-bottom: space-4` |
| After page header | `margin-bottom: space-3` |
| Inside containers | `padding: space-2` |
| List items | `gap: space-2` on parent |
| Form fields | `gap: space-2` on parent |
| Label to input | `gap: space-1` |
| Title to subtitle | `margin-bottom: space-1` |
| Icon to text | `gap: space-0` or `space-1` |
| Form actions from form | `margin-top: space-3` |
| Buttons in a row | `gap: space-1` |

#### Border Radii

| Variable | Value | Usage |
|----------|-------|-------|
| `--theme-ui-radii-small` | 3px | Badges, small elements |
| `--theme-ui-radii-default` | 6px | Buttons, inputs, cards |
| `--theme-ui-radii-large` | 12px | Modals, large containers |

#### Component Patterns

##### Buttons

Two button styles exist and should be used consistently:

```css
/* Primary button (green) - for main actions */
.repository-button {
  background-color: var(--theme-ui-colors-button-primary-bg);
  color: var(--theme-ui-colors-button-primary-fg);
}

/* Secondary button (gray) - for cancel, secondary actions */
.repository-button-secondary {
  background-color: var(--theme-ui-colors-button-default-bg);
  color: var(--theme-ui-colors-button-default-fg);
  border: 1px solid var(--theme-ui-colors-button-default-border);
}
```

**Button guidelines:**
- Use primary (green) for the main action on a page
- Use secondary (gray) for cancel, back, or alternate actions
- Always include focus states with `outline: 2px solid var(--theme-ui-colors-primary)`
- Buttons should be `5px 16px` padding with 20px line-height

##### Form Inputs

```css
.input {
  padding: 5px 12px;
  font-size: 14px;
  line-height: 20px;
  background-color: var(--theme-ui-colors-control-bg);
  border: 1px solid var(--theme-ui-colors-control-border);
  border-radius: var(--theme-ui-radii-default);
}

.input:focus {
  border-color: var(--theme-ui-colors-primary);
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.3);
}
```

**Input guidelines:**
- All inputs should have visible focus rings (box-shadow)
- Error states use `--theme-ui-colors-danger` for border
- Placeholders use `--theme-ui-colors-muted`

##### Cards and Containers

```css
.card {
  padding: var(--theme-ui-space-2);
  background-color: var(--theme-ui-colors-background);
  border: var(--theme-ui-borders-thin);
  border-radius: var(--theme-ui-radii-default);
}

.card:hover {
  border-color: var(--theme-ui-colors-primary);
}
```

##### Page Headers

Use the `.page-header` component for consistent page titles:

```css
.page-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  margin-bottom: var(--theme-ui-space-3);
  padding-bottom: var(--theme-ui-space-2);
  border-bottom: var(--theme-ui-borders-thin);
}
```

#### File Organization

```
assets/css/
├── theme/
│   └── tokens.css          # All design tokens and base styles
├── components/
│   └── error_boundary.css  # Shared component styles
├── routes/
│   ├── navbar.css          # Navigation
│   ├── footer.css          # Footer
│   ├── auth.css            # Login/register pages
│   ├── repositories.css    # Repository list and forms
│   └── <page>.css          # Page-specific styles
└── app.css                 # Import all stylesheets
```

#### Best Practices

1. **Extract shared patterns**: If a style is used in 3+ places, move it to `tokens.css`
2. **Use semantic class names**: `.repository-card` not `.blue-box`
3. **Avoid magic numbers**: Use spacing/sizing variables
4. **Mobile-first**: Write base styles, then add `@media` for larger screens
5. **Test both themes**: Always verify styles in light AND dark mode
6. **Focus states**: Every interactive element needs visible focus styling
7. **Transitions**: Use `0.15s` or `0.2s ease` for hover/focus transitions

#### Creating New Pages

1. Create `assets/css/routes/<page>.css`
2. Import it in `assets/css/app.css`
3. Use existing component classes (`.repository-button`, `.repository-input`, etc.)
4. Only add new styles if existing ones don't fit
5. Follow the naming pattern: `.<page>-<element>` (e.g., `.import-repo-list`)
6. **Verify CSS classes exist** - If you add a class in a template, ensure it's defined in CSS

##### Common Classes Checklist

When creating a list page, ensure these classes are styled:

```css
/* Container for the page */
.<page>-container { }

/* List of cards/items - MUST have gap */
.<page>-list {
  display: flex;
  flex-direction: column;
  gap: var(--theme-ui-space-2);
}

/* Individual card - MUST have internal spacing */
.<page>-card {
  padding: var(--theme-ui-space-2);
  border: var(--theme-ui-borders-thin);
  border-radius: var(--theme-ui-radii-default);
}

/* Card title - MUST use heading font */
.<page>-card-name {
  font-family: var(--theme-ui-fonts-heading);
  font-size: var(--theme-ui-font-size-md);
  font-weight: var(--theme-ui-font-weights-semibold);
  margin-bottom: var(--theme-ui-space-0);
}

/* Card subtitle/handle */
.<page>-card-handle {
  color: var(--theme-ui-colors-muted);
  font-size: var(--theme-ui-font-size-sm);
  margin-bottom: var(--theme-ui-space-2);
}

/* Card description */
.<page>-card-description {
  color: var(--theme-ui-colors-text);
  margin-bottom: var(--theme-ui-space-1);
}

/* Card actions */
.<page>-card-actions {
  display: flex;
  gap: var(--theme-ui-space-1);
  margin-top: var(--theme-ui-space-2);
}

/* Empty state */
.<page>-empty {
  text-align: center;
  padding: var(--theme-ui-space-4);
  color: var(--theme-ui-colors-muted);
}
```

#### Dark Mode

Dark mode is automatic via `prefers-color-scheme` media query and can be manually toggled with `data-theme` attribute:

```css
/* System preference (default) */
@media (prefers-color-scheme: dark) {
  :root { /* dark values */ }
}

/* Manual override */
:root[data-theme="dark"] { /* dark values */ }
:root[data-theme="light"] { /* light values */ }
```

Always test both modes. Some colors need explicit dark mode versions (like focus ring colors using rgba).
