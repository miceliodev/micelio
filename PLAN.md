# PLAN

This document is the canonical product and architecture plan for Micelio. It folds
together the current design direction, accepted decisions, and active work. Older
roadmap, ADR, and plan documents remain as historical context until they are pruned
or rewritten.

## Current Direction

- Micelio is the forge.
- `hif` is the version control system.
- Repositories are the primary container for code and history.
- Sessions are the durable, portable unit of code-changing work.
- Landings advance repository positions via compare-and-swap over S3-compatible
  object storage.
- Remote reads, lazy materialization, and index-driven search are first-class.
- Sandboxed execution is a core capability, not a side feature.

## Terminology

- **Repository**: the code container and history boundary. Older docs may call this
  a "project".
- **Position**: an accepted repository state after landing.
- **Session**: the durable unit of work containing goal, conversation, decisions,
  file changes, attribution, and status.
- **Workspace**: a local materialization and cache of repository paths.
- **Workflow**: a repository-defined program, stored as a constrained `.exs` DSL,
  that can drive deterministic and non-deterministic work.
- **Workflow run**: one execution of a workflow against a repository and, when
  needed, a session.
- **Sandbox**: a managed execution environment for workflow or session work.

## Product Model

### Repositories and Positions

- A repository owns a `head`, append-only landing records, tree snapshots, and
  blobs.
- Landing is CAS-based against the current repository head.
- Conflict detection should be path-aware and explainable.
- Read APIs should work by position, tree, blob, and path without requiring a full
  checkout.
- Search should be index-driven, not raw object scans.

### Sessions

- Sessions are the unit of collaboration, review, and audit.
- Sessions must sync continuously to Micelio while work is in progress.
- A draft session should be inspectable live and resumable from anywhere.
- Code-changing work should be session-backed.
- A session can start locally or in a sandbox and move between those environments
  before landing.
- Session portability is a core requirement, not an optimization.

### Local and Sandbox Execution

- Local workflow: a developer runs agentic work from a local workspace and pushes
  session progress continuously to Micelio.
- Sandboxed workflow: a developer starts work in a managed sandbox, lets the
  system execute agentic steps remotely, and can later resume or polish that same
  session locally.
- The remote-started and local-resumed flow must use the same session model and
  protocol.
- Sandbox execution should use explicit sandbox profiles and capture logs,
  artifacts, and status transitions.

### Workflows

- Workflows are repository-defined programs stored as constrained `.exs` files.
- A workflow describes what should happen in a session and may combine
  deterministic steps with non-deterministic prompt-driven steps.
- Running a workflow should produce durable artifacts in the session when the work
  is session-backed.
- A session has at most one workflow attached.
- Not every remote task needs a session. Short-lived debugging or user-request
  investigation may run without creating one.
- The exact workflow DSL design is intentionally deferred.

## Accepted Decisions

- Sessions, not commits, are the primary unit of change and audit.
- S3-compatible object storage is the source of truth, with tiered caching above
  it.
- `hif.v1` should be the session, content, and search protocol surface.
- Repository reads should support lazy materialization and remote-first access.
- Remote search and grep should be backed by an index service.
- Agent execution should carry explicit sandbox policy.
- ActivityPub federation remains a possible direction, but it is not a near-term
  focus.

## Active Work

1. Repository protocol and landing correctness
   - Finalize the session-native repository protocol.
   - Harden `head` and position storage, CAS landing, and conflict diagnostics.
2. Remote-first repository access
   - Deliver tree, path, blob, and blame APIs by position.
   - Support lazy workspace materialization and controlled prefetch.
   - Make grep and search index-driven and explicit about index freshness.
3. Session sync and portability
   - Keep draft sessions continuously synced to Micelio.
   - Allow live observation, takeover, and resume across machines and
     environments.
   - Preserve one session identity across local and sandbox execution.
4. Sandboxed execution
   - Let developers spawn managed sandboxes for agentic work.
   - Capture logs, artifacts, and execution history in Micelio.
   - Make sandbox execution compatible with later local takeover of the same
     session.
5. Workflow system
   - Add repository-local workflow definitions in constrained `.exs`.
   - Keep the DSL intentionally smaller than general Elixir.
   - Support both deterministic steps and prompt-driven steps.
   - Defer exact syntax, packaging, and runtime boundaries until after the core
     session model is solid.
6. Engineering foundations
   - Remove outdated `project` and `mic` terminology from code and docs where it
     obscures the model.
   - Reduce global state in tests so more of the suite can run concurrently.
   - Keep protocol docs and help output aligned so agents can understand `hif`
     from first-party surfaces.

## Deferred or Later

- ActivityPub federation
- Exact workflow DSL design
- Cross-repository rebase and review UX beyond core session landing
- Broader governance and scaling work that depends on the core protocol settling
  first

## Historical Notes

- Older docs may use `mic` where the current system is `hif`.
- Older docs may use `project` where the current system is `repository`.
- Older plan files may describe completed implementation steps or intermediate
  designs. Use this file as the current source of truth when they conflict.

## Source Material Folded Here

- `docs/contributors/next.md`
- `docs/refactoring-plan.md`
- `docs/compute/mic-integration-design.md`
- `docs/adr/*.md`
- `build/adr/0005-session-native-repo-protocol.md`
- `build/plans/2026-02-27-virtual-vcs-build-plan.md`
