---
title: "fix: Enable mic land to push local workspace to micelio.dev"
type: fix
date: 2026-01-29
---

# fix: Enable mic land to push local workspace to micelio.dev

## Overview

Introduce an explicit **workspace linking** step so a local workspace can be mapped to a remote Micelio project (forge) before landing. The link accepts either a full web URL (e.g., `https://micelio.dev/micelio/micelio`) or a short ref (`micelio/micelio`), infers the gRPC endpoint, and stores the mapping in `.mic/`. After linking, `mic land` works from an existing local directory by using the stored mapping.

## Problem Statement / Motivation

`mic land` currently depends on `.mic/workspace.json` (created by `mic checkout`) to know which remote project to land to. In a pre-existing local project directory, there is no mapping between the local workspace and the remote project, so landing fails even when authentication works and the remote project exists. We need a Git-like, explicit “link remote” step to map the local workspace to a project before landing, without forcing a checkout.

## Repository Research Summary

### Architecture & Structure
- The CLI uses workspace metadata to land: `mic/src/workspace.zig` loads `.mic/workspace.json`, computes local changes, then starts and lands a session via gRPC. (`mic/src/workspace.zig`)
- Workspace metadata is stored in `.mic/workspace.json` and includes server, account, project, tree hash, and entries. (`mic/src/workspace/manifest.zig`)
- Default server config includes micelio.dev with gRPC at `https://api.micelio.dev:443` and web at `https://micelio.dev`. (`mic/src/config.zig`)
- `mic checkout` builds the workspace from the server head tree and writes files + manifest. (`mic/src/workspace.zig`)

### Issue Conventions
- No GitHub issue templates in `.github/ISSUE_TEMPLATE/`.

### Documentation Insights
- User docs describe session workflows (`mic session start` → `mic session land`). (`docs/users/mic-workflows.md`)
- Design docs outline landing as merging session diff into base and updating project head. (`priv/docs/shapers/design.md`)

### Templates Found
- None.

### Implementation Patterns
- CLI commands parse and validate args in `mic/src/main.zig` and delegate to modules like `workspace.zig` or `session.zig`.
- Workspace operations use gRPC endpoints and tokens (`auth.requireTokensWithMessage`).

## Institutional Learnings Search Results

### Search Context
- **Feature/Task**: Make `mic land` work for existing local projects against micelio.dev
- **Keywords Used**: land, workspace, checkout, micelio.dev, gRPC
- **Files Scanned**: 0 (no `docs/solutions/` directory found)
- **Relevant Matches**: 0

### Critical Patterns (Always Check)
- No `docs/solutions/patterns/critical-patterns.md` found in this repo.

### Relevant Learnings
- None found.

### Recommendations
- Proceed with local repo patterns; document any new lessons in future `docs/solutions/` if applicable.

## Research Decision

Strong local context exists (workspace, config, landing flow are documented and implemented locally), and this is not a high-risk external integration. Proceeding without external research.

## SpecFlow Analysis (User Flow Gaps)

### User Flow Overview
1. **Link workspace with URL**: User is authenticated → runs `mic link https://micelio.dev/micelio/micelio` inside a local project dir → CLI infers gRPC endpoint, resolves project, and writes `.mic/workspace.json`.
2. **Link workspace with ref**: User runs `mic link micelio/micelio` → CLI uses default server config to resolve project and writes `.mic/workspace.json`.
3. **Land after link**: User runs `mic land "<goal>"` → CLI uses stored mapping and lands all local changes.
4. **No link**: User runs `mic land` without `.mic/` → CLI errors and instructs to run `mic link`.
5. **Auth/server mismatch**: tokens are for different server than inferred server → CLI prompts re-auth.
6. **Errors**: invalid URL, project not found, gRPC errors, or conflicts show actionable guidance.

### Missing Elements & Gaps
- **Linking command**: No explicit way to map a local workspace to a remote project.
- **Server inference**: Need a rule to infer gRPC endpoint from a web URL.
- **Default server**: Decide behavior when the user provides a short ref (`org/project`) with no URL.
- **Success criteria**: define what “landed” means after linking (landing position, head tree updated, `mic log` shows session).

### Critical Questions Requiring Clarification
1. **Critical**: Confirm `mic link` is the canonical command (not `mic workspace link`) for mapping a local workspace to a remote project.
2. **Critical**: Confirm `mic link` accepts either a full URL or a short ref (`org/project`).
3. **Important**: Confirm short ref uses the **default server** from config; no interactive server selection.
4. **Important**: Confirm landing requires a linked remote; `mic land` should error if `.mic/` is missing.

### Recommended Next Steps
- Define bootstrap UX (flags/command), safety rules, and server resolution, then update acceptance criteria accordingly.

## Proposed Solution

Add an explicit **workspace linking** command that maps a local workspace to a remote project, then require that mapping for landing:

- **CLI UX**: Add `mic link <target>` where `<target>` is either:
  - A full web URL: `https://micelio.dev/<org>/<project>`
  - A short ref: `<org>/<project>` (uses default server from config)
- **Link behavior**:
  - Resolve target to `server (gRPC URL) + org + project`.
  - Validate authentication against that server.
  - Write `.mic/workspace.json` (manifest-only) with `server`, `account`, `project`, empty `entries`, and remote `tree_hash` if available.
- **Landing flow**: `mic land` requires `.mic/workspace.json`. If missing, error: “No workspace link. Run `mic link <org/project>` or `mic link <url>`.”
- **Server handling**: Infer gRPC endpoint from web URL (e.g., `https://micelio.dev/...` → `https://api.micelio.dev:443`). This is an explicit convention for now; future config can override.
- **Docs**: Update `docs/users/mic-workflows.md` to include “Link existing local project” and the URL/ref examples.

## Technical Considerations

- **Workspace metadata**: `workspace.land` depends on `.mic/workspace.json`; linking should write a minimal valid manifest in `.mic/`. (`mic/src/workspace/manifest.zig`)
- **Remote head fetch**: Use ContentService/GetHeadTree to capture the current tree hash for the linked project. (`mic/src/workspace.zig`)
- **Config defaults**: If `mic link` receives `org/project`, use default server config; for URLs, derive gRPC endpoint by convention (e.g., `micelio.dev` → `api.micelio.dev:443`). (`mic/src/config.zig`)
- **Safety**: Linking must not write or overwrite workspace files; only `.mic/` metadata.

## Acceptance Criteria

- [x] Running `mic link https://micelio.dev/micelio/micelio` in an existing local project creates `.mic/workspace.json` with the correct `server`, `account`, and `project`.
- [x] Running `mic link micelio/micelio` uses the default server and creates `.mic/workspace.json`.
- [x] Running `mic land "<goal>"` without `.mic/` errors with “No workspace link. Run `mic link <org/project>` or `mic link <url>`.” and exits non-zero.
- [x] After linking, `mic land "<goal>"` lands all local changes to the remote project and prints the landing position.
- [x] If tokens are for a different server than the inferred server, `mic link` prints re-auth guidance and exits non-zero.
- [x] Documentation describes the link flow and URL/ref examples.

## Success Metrics

- First-time bootstrap to micelio.dev completes with `mic link` + `mic land` in a local project directory.
- Support incidents or user confusion about “No workspace metadata found” for this flow are eliminated.

## Dependencies & Risks

- **Risk**: Incorrect URL → gRPC inference could misroute requests. Mitigate with explicit error messaging and tests.
- **Dependency**: ContentService/GetHeadTree and SessionService/LandSession must be reachable at the inferred gRPC URL.

## Implementation Notes (Non-Code)

- Create a helper: `workspace.linkManifest(account, project, server, path)` that only writes `.mic/workspace.json` and captures remote tree hash.
- Add command-line parsing and usage text in `mic/src/main.zig` for `mic link`.
- Update `docs/users/mic-workflows.md` with a new “Link existing local project” section.
- Add or update CLI tests in `mic/tests/integration.zig` for the link flow and failure modes.
  - `test "link with url writes manifest"`
  - `test "link with org/project uses default server"`
  - `test "land errors without link"`
  - `test "link errors on auth server mismatch"`

## AI-Era Considerations

- If AI tooling is used for implementation, require human review of any file-system safety changes and gRPC error handling.
- Prefer explicit tests to confirm bootstrap does not overwrite local files.

## References & Research

### Internal References
- `mic/src/workspace.zig` (landing flow, gRPC calls, change detection)
- `mic/src/workspace/manifest.zig` (workspace metadata format)
- `mic/src/config.zig` (default server config for micelio.dev)
- `docs/users/mic-workflows.md` (user workflows)
- `priv/docs/shapers/design.md` (landing semantics)

### Related Work
- `docs/contributors/next.md` (mentions basic CLI commands including land)
