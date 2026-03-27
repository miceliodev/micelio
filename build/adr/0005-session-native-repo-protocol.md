# 0005 Session-native repository protocol for monorepo-scale systems

Date: 2026-02-27
Status: Accepted

## Context

Micelio already models repository updates as sessions, not commits, and stores
repository state in S3-compatible object storage. The next iteration needs a formal
shape for:

- repository state and positions,
- session intent + decisions + file diffs,
- conflict handling at scale,
- remote content queries (grep-like search) without cloning.

Large monorepos need "local feel" with no full checkout and no linear operations on
full repository snapshots.

## Decision

Adopt a **Session-native protocol layer** with four coordinated APIs:

1. **Session API**: lifecycle for sessions (`start`, `append`, `land`, `abandon`,
   `status`).
2. **Tree/Blob API**: immutable reads by hash/position with lazy path materialization.
3. **Position API**: atomic head transitions and landing logs.
4. **Search API**: remote text search over repository history and current position.

All repository writes and mutable state transition through the Position API as append-only
landing records. Search and file reads are index-driven, never full-object scans.

## Design

### 1) Repository identity and progression

- A repository owns:
  - `head` pointer (current accepted position),
  - append-only landing records,
  - persistent tree snapshots and blobs in CAS.
- A session is always created with a base position (`base_position`) and can only land
  if its patch is validated against the current head at land-time.
- Landing is **CAS-based**:
  - read current `head_etag`,
  - apply conflict checks (bloom + exact path verification),
  - write new head only if `head_etag` still matches.

### 2) Session structure

- A session must carry:
  - `goal` (why),
  - `conversation` (human/agent context),
  - `decisions` (what changed and why),
  - `file_ops` (concrete mutations),
  - `attribution` (agent/tool/user metadata),
  - `status`.
- A session is not just a diff; it is the unit of workflow, audit, and review.

### 3) Working model

- Workspace clients keep local metadata only for requested paths.
- Default read paths are remote (`repo + path + position`) with optional local cache.
- Lazy materialization is supported through manifest + on-demand `GetPath` + prefetch by
  directory context.

### 4) Search (`grep`) model at scale

- No CLI `grep` implementation scans all repository objects.
- `mic grep` executes against a dedicated **SearchIndexService**:
  - index producers subscribe to landing events,
  - query API supports repo-scope, path filters, regex/substring modes,
  - return matches with `position`, `path`, `line`, `column`, `snippet`,
    `session_id`, `author`.
- If index is unavailable, clients get actionable fallback:
  - "index stale" + optional `--local` mode when workspace is materialized.

### 6) Protocol cutover

- `hif.v1` is the only supported session/content/search protocol surface.
- Legacy session/content compatibility endpoints are not part of the runtime contract.

### 5) Conflict model

- Land-time conflict checks are staged:
  1. O(1) / O(log n) bloom overlap check,
  2. exact overlap confirmation on conflicting paths,
  3. conflict result includes path-level diagnostics.
- Land conflicts produce explicit `session.conflict` records and preserve the session for
  agent-assisted or human-assisted resolution.

## Storage implications

- Primary writes remain to S3-compatible CAS:
  - `blobs/{hash}`,
  - `trees/{hash}`,
  - `sessions/{id}.jsonl`,
  - `head.bin`,
  - `landing/{position}.json`,
  - `index/path/...` and `index/search/...`.
- Metadata and query paths are strongly typed and immutable once written.

## Consequences

- Satisfies monorepo usage: no full clone required for most operations.
- Enables high-parallelism: independent sessions can be started continuously from the
  same head and resolved on landing.
- Makes review/audit straightforward: every change can include rationale and context.
- Requires: protocol evolution, search index lifecycle, and landing/index replay
  tooling before broad adoption.
