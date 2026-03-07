# Virtual VCS Build Plan (Monorepo Scale, S3-first)

Date: 2026-02-27

## Objective

Deliver a session-native versioning system for monorepo scale where:
- clients run without full checkout,
- remote search (`grep`) is index-driven,
- landing is conflict-aware and scalable,
- all protocol surfaces are explicit and evolvable.

## Execution Principles

- **Session-first, position-second**: sessions are first-class; landing produces the next position.
- **No raw S3 scans for queries**: grep/search always uses index services.
- **Schema-driven progress**: protocol contract defined before endpoint implementation.
- **Observable-by-default**: every command emits structured event/error metadata for agents.

## Milestones

### Milestone 0 — Protocol freeze (days 1-2)

1. Finalize `build/protocols/micelio_virtual_vcs_v1.proto`.
2. Define RPC mapping to existing services:
   - `micelio.sessions.v1` => session lifecycle compatibility layer,
   - `micelio.content.v1` => tree/blob/blame/grep reads,
   - new search service methods if additive compatibility allows.
3. Add ADR and architecture notes to ADR index (`build/adr/0005...` already added).
4. Add contract tests for:
   - required/optional field rules,
   - conflict payload shape,
   - pagination behavior for search responses.

### Milestone 1 — Canonical head/landing core (weeks 1-2)

1. Introduce explicit `RepositoryHead` object in storage:
   - `{position, tree_hash, etag, updated_at}`.
2. Update landing path:
   - session base captured at open,
   - exact CAS write with if-match,
   - immutable landing record append.
3. Persist session overlay data in:
   - `sessions/{id}.jsonl`,
   - `landing/{position}.json`,
   - path touch bloom index.
4. Add landing outcome events: `landed`, `conflict`, `rejected`.
5. Acceptance criteria:
   - concurrent session launches succeed,
   - conflicting sessions detect and return deterministic path overlaps,
   - head advances only on successful landing.

### Milestone 2 — Remote read + lazy workspace (weeks 2-4)

1. Implement content read APIs by `position/tree`:
   - `GetHeadTree`, `GetTree`, `GetPath`, `GetBlob`, `Blame`.
2. Add workspace manifest format to support sparse/lazy mode:
   - materialize only paths in active task set,
   - add explicit prefetch policy by directory context.
3. Implement fallback if index stale:
   - surface exact error message and stale index revision.
4. Acceptance criteria:
   - open project with no checkout,
   - `mic ls` and `mic cat` operate with no local files for paths outside manifest,
   - sync only transfers changed paths.

### Milestone 3 — Remote grep/search service (weeks 4-6)

1. Add write-time index producer:
   - consume landing stream,
   - tokenize text files into postings segments.
2. Add search service:
   - query by regex/substring,
   - prefix + glob path filtering,
   - offset/limit + continuation token paging.
3. Add `mic grep` command:
   - defaults to latest position,
   - optional `--position`, `--path`, `--regex`, `--case-sensitive`.
4. Add offline fallback:
   - `--local` uses workspace cache only and errors if paths absent.
5. Acceptance criteria:
   - grep on 100k files runs on index path (<500ms p95 for small queries),
   - index rebuild recovers from missed landing events.

### Milestone 4 — Conflict resolution workflow (weeks 6-7)

1. Add conflict explainability endpoint on landing failure:
   - `position`, `paths`, `touched_by`, `possible_merge_action`.
2. Add session "continue" workflow:
   - append more events after conflict,
   - keep same session id,
   - reland with revalidation from latest head.
3. Add resolver command:
   - agent-assisted and operator-assisted conflict resolution,
   - explicit "take upstream", "keep session", or "split session" options.
4. Acceptance criteria:
   - a conflict session can be retried without creating a brand-new session.

### Milestone 5 — Scalability and governance hardening (weeks 8-10)

1. Shard search index by repository and path range.
2. Add per-repository retention + lifecycle for index snapshots.
3. Add periodic rollups for:
   - bloom filter checkpoints,
   - landing path statistics,
   - search latency/error budget.
4. Add audit exports:
   - immutable landing record digest chain,
   - session event timeline export.
5. Acceptance criteria:
   - query and landing SLAs documented with health dashboard,
   - chaos test for S3 transient failures and index lag.

## Delivery order (practical sequence)

1. Protocol/doc freeze (`ADR + proto + tests`)  
2. Head/landing correctness (`if-match` + conflict checks)  
3. Content APIs + workspace lazy materialization  
4. Search index and `mic grep`  
5. Conflict UX and retry loop  
6. Scale features + admin observability

## Interface compatibility

- Keep existing endpoints callable for the initial release.
- New v1 protocol fields are additive; old clients ignore unknown fields.
- New functionality (search, position-first reads, richer conflict diagnostics) is introduced with
  feature flags so rollout is controlled.

## Risks

- **Index lag risk**: search may return slightly stale results.  
  Mitigation: include index revision in every match.
- **Storage fan-out risk**: too many small index shards.  
  Mitigation: adaptive compaction by write rate.
- **Protocol drift risk**: CLI method names currently diverge from proto files.  
  Mitigation: add explicit compatibility matrix and deprecation window.

## Non-goals for v1

- full cross-repository rebasing UI,
- full bidirectional sync protocol with third-party VCS as primary transport,
- global repository-wide regex engines beyond per-repo scoped text index.
