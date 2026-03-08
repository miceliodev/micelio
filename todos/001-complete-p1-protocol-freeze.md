---
status: complete
priority: p1
issue_id: "001"
tags: [virtual-vcs, protocol, grpc, sessions]
dependencies: []
---

# Protocol Freeze for Session-native Monorepo Architecture

## Problem Statement

Micelio is shifting to a session-native repository protocol with monorepo-scale requirements
and remote-first operations. We need a frozen protocol contract before implementing protocol
surface changes so clients and services do not diverge while scaling.

## Findings

- `build/adr/0005-session-native-repo-protocol.md` was created and outlines session/position
  semantics, landing strategy, and search model.
- `build/protocols/hif_v1.proto` and `build/adr/0005...` were moved under
  `build/` to keep build artifacts separate from user-facing docs.
- Existing gRPC modules remain on legacy `micelio.sessions.v1` and `micelio.content.v1`
  contracts and are still in active use.
- There is no current contract test suite asserting field-level expectations (required fields,
  paging shape, conflict payload shape, or service continuity) for the new protocol draft.

## Proposed Solutions

### Option 1: Freeze-then-implement

**Approach:** Finalize proto and ADR now, add compatibility matrix and contract tests before
any runtime implementation of new services.

**Pros:**
- Prevents untracked protocol drift during implementation.
- Creates explicit upgrade and migration path from legacy services.
- Gives `mic` CLI maintainers stable artifacts for self-documentation.

**Cons:**
- Slight delay before endpoint changes can proceed.

**Effort:** 4-6 hours

**Risk:** Medium

### Option 2: Implement first, normalize protocol after

**Approach:** Continue endpoint and storage work using existing docs and retroactively lock
proto after major paths are implemented.

**Pros:**
- Faster initial delivery of service code.
- Lower upfront documentation overhead.

**Cons:**
- High risk of incompatible client/server decisions.
- Rework likely once protocol settles.

**Effort:** 2-3 hours plus likely rework

**Risk:** High

## Recommended Action

Proceed with Option 1. Create an explicit protocol freeze by:
- marking ADR as accepted,
- adding a compatibility mapping doc for existing `micelio.sessions.v1`/`micelio.content.v1`,
- adding contract tests that assert required request/response fields and pagination structures.

## Technical Details

Affected files:
- `build/adr/0005-session-native-repo-protocol.md`
- `build/protocols/hif_v1.proto`
- `build/protocols/hif_v1.compatibility.md` (new)
- `test/micelio/protocol/virtual_vcs_contract_test.exs` (new)

Related components:
- `lib/micelio/grpc/sessions_server.ex`
- `lib/micelio/grpc/content_server.ex`
- CLI mapping in Rust `mic` (reference for future client updates).

## Acceptance Criteria

- [x] ADR 0005 status is set to "Accepted" for protocol freeze milestone.
- [x] New compatibility mapping explicitly links existing service methods to new virtual-vcs services.
- [x] Contract tests are in place for:
  - required request/response fields,
  - conflict payload shape,
  - paging fields for search responses.
- [x] Protocol document references include the contract-test intent and backward-compatible mapping.

## Work Log

### 2026-02-27 - Track Protocol Freeze

**By:** Claude Code

**Actions:**
- Confirmed no existing `todos/` system files were present.
- Created issue-tracked file entry for Step 1 with p1 priority.
- Established a concrete acceptance checklist for protocol freeze.

**Learnings:**
- The repo has extensive existing gRPC tests and protocol modules, so adding explicit
  protocol contract tests is low-risk and should be enforceable via normal unit test runs.

### 2026-02-27 - Complete Freeze + Validation

**By:** Claude Code

**Actions:**
- Added `build/protocols/hif_v1.compatibility.md` and updated
  `build/protocols/README.md` with the mapping.
- Moved ADR status to Accepted in `build/adr/0005-session-native-repo-protocol.md`
  and added a compatibility subsection.
- Added required/optional field annotations plus `SessionConflict` payload in
  `build/protocols/hif_v1.proto`.
- Added `test/micelio/protocol/virtual_vcs_contract_test.exs` with service/field/conflict/paging
  coverage and verified with `mix test`.

**Learnings:**
- Contract tests can be enforced as soon as proto changes land and guard against accidental drift.
- Compatibility mappings should remain explicit artifacts, separate from implementation docs.

## Notes

- `agent-trace` and agentprotocol references should be cross-linked later in Step 1
  compatibility docs once finalized.
