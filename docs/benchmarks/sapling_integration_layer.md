# Sapling integration layer design

This design outlines the integration layer between mic and Sapling for
stacked session workflows while preserving Git interoperability.

Started at: 2026-01-21T00:30:00Z

## Goals

- Provide a single VCS adapter surface for Git and Sapling-backed projects.
- Keep mic session metadata authoritative while enabling Sapling stacked commits.
- Preserve Git interoperability and allow fallback to Git-backed repos.
- Avoid blocking requests on slow CLI calls by keeping all operations bounded.

## Non-goals

- Replace mic storage formats or rewrite mic session primitives.
- Expose every Sapling feature through the Forge UI on day one.
- Require Sapling on all hosts; Git must remain supported.

## Assumptions

- Sapling is accessed via the `sl` CLI and may be missing on some hosts.
- A repository can be Git-native or Sapling git-backed; detection is required.
- Existing Git Zig NIFs remain the default implementation for Git-backed repos.

## Integration layers

- Micelio.VCS behaviour defining repo_init/status/log/tree/blame/commit APIs.
- Micelio.VCS.Git implementation backed by existing Zig NIFs.
- Micelio.VCS.Sapling implementation backed by `sl` CLI calls with parsing.
- Micelio.Sapling.Adapter responsible for mapping mic sessions to Sapling stacks.
- Micelio.RepoMetadata storing repo backend and Sapling-specific settings.

## Adapter contract

- repo_init(path, backend) -> {:ok, metadata} | {:error, reason}
- status(path) -> {:ok, changes}
- log(path, opts) -> {:ok, commits}
- tree_list(path, ref, dir) -> {:ok, entries}
- tree_blob(path, ref, file) -> {:ok, blob}
- commit(path, message, opts) -> {:ok, commit_id}
- stack_view(path, opts) -> {:ok, stack}
- push(path, remote, opts) -> {:ok, result}

## Data model

- Add `projects.vcs_backend` enum: git | sapling (default git).
- Add `projects.vcs_root` (path) to locate the working copy.
- Store Sapling-specific configuration as JSON (e.g., default stack branch).
- Persist session-to-commit mappings in `sessions.vcs_commit_id`.

## Session mapping

- Each mic session becomes a Sapling stack commit with a trailer: `Mic-Session: <id>`.
- Session metadata is mirrored in DB; Sapling remains the code DAG only.
- Expose a `refs/mic/sessions/<id>` marker for Git interoperability.
- Use stack ordering to mirror mic session ordering for review.

## Rollout plan

- Phase 1: introduce adapter behaviour + read-only ops (status/log/tree).
- Phase 2: enable session commits + stack view for Sapling-backed repos.
- Phase 3: integrate push/pull flows and expose UI toggles per project.

## Risks

- Sapling CLI output parsing drift between versions.
- Git interoperability gaps for Sapling git-backed repos.
- Performance variance when shelling out for large repos.

## Open questions

- Should Sapling be required only for new projects or also allow migrations?
- Which Sapling stack view should power the web UI (stack vs log)?
- Do we need a dedicated worker pool for long-running Sapling commands?
