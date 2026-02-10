%{
  title: "Design",
  description: "Unified engineering design for mic and Micelio."
}
---

Micelio and mic are a forge and version control system designed for agent-first development. The system is built to capture not only what changed, but why it changed, while scaling to large projects with low operational cost.

## The big picture

Micelio is not another Git forge. It is a system built for an agent-first workflow where many concurrent agents operate across large projects and humans focus on review and direction. mic provides the version control model, and Micelio is the forge that makes session history legible, reproducible, and auditable.

## The problem

### Current reality (Git + GitHub)

- Snapshot-based commits hide iterations and intermediate reasoning.
- Human-centric workflows do not scale to many agents.
- Performance degrades with project size and activity.
- Branch and merge complexity becomes a bottleneck at scale.
- Reasoning and decisions live outside version control.

### Agent-first future

- Hundreds of AI agents working concurrently on codebases.
- Billions of files in monorepos.
- Hundreds of thousands of changes per day.
- Continuous exploration, backtracking, and decision making.
- Humans reviewing and directing rather than writing most code.

Git cannot handle this future. The system needs new primitives.

## Design goals

- Capture reasoning and decisions alongside code changes.
- Scale to monorepos with predictable performance.
- Keep the forge stateless and horizontally scalable.
- Minimize long-lived state and operational cost.
- Make landing atomic and conflict detection fast.

## Sessions, not commits

The session is the unit of work. It bundles goal, conversation, decisions, and changes into a single artifact that can be inspected or replayed.

A session captures:
- Goal: what the work is trying to accomplish.
- Conversation: dialogue between agents and humans.
- Decisions: why the change took a particular direction.
- Changes: the actual file modifications.

Example session:

```
Session: "Add authentication to API"
├── Goal: Implement secure login/logout endpoints
├── Conversation
│   ├── Human: "Use JWT tokens for auth"
│   ├── Agent: "Should I store sessions in Redis?"
│   ├── Human: "No, keep JWT stateless"
│   └── Agent: "Implementing with bcrypt for passwords"
├── Decisions
│   ├── "JWT chosen over sessions per human preference"
│   ├── "Bcrypt for password hashing - industry standard"
│   └── "Auth middleware in /middleware - follows existing pattern"
└── Changes
    ├── + src/auth/jwt.zig
    ├── + src/middleware/auth.zig
    └── ~ src/main.zig (added auth routes)
```

Session lifecycle:
- Start: capture the current project tree hash and session metadata.
- Edit: changes create new content-addressed blobs and update a session tree.
- Land: merge the session tree into a new project tree and update head atomically.

## Architecture overview

mic has three components that work together:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                               CLIENT (Zig)                                   │
│                                                                             │
│  Core modules (hash, bloom, HLC, tree) are embedded in the CLI.            │
│                                                                             │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                  │
│  │   mic CLI     │  │   mic-fs      │  │  Tiered Cache │                  │
│  │               │  │  (Phase 2)    │  │               │                  │
│  │ checkout      │  │  NFS daemon   │  │  RAM → SSD    │                  │
│  │ land          │  │  Mount point  │  │  → S3         │                  │
│  └───────────────┘  └───────────────┘  └───────────────┘                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ gRPC
                                    │
┌─────────────────────────────────────────────────────────────────────────────┐
│                    FORGE (stateless agents, like WarpStream)                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      Stateless Agents (Fly.io / Lambda / K8s)       │   │
│  │                                                                     │   │
│  │   Any agent can handle any request (no leader, no partitioning)    │   │
│  │   Auth · Session CRUD · Blob streaming · Landing                   │   │
│  │   Auto-scale based on CPU, scale to zero when idle                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                         │
│                          S3 Conditional Writes                              │
│                          (if-match / if-none-match)                         │
│                                   │                                         │
│                    No coordinator needed for landing                        │
│                    S3 provides atomic compare-and-swap                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         S3 (source of truth)                                 │
│                                                                             │
│   Object storage-first, not tiered                                          │
│                                                                             │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│   │   Landing   │  │   Session   │  │    Tree     │  │    Blob     │       │
│   │     Log     │  │    Store    │  │    Store    │  │    Store    │       │
│   │             │  │             │  │             │  │             │       │
│   │ Append-only │  │   Binary    │  │   Binary    │  │   zstd      │       │
│   │ Bloom index │  │   format    │  │   B+ tree   │  │  content-   │       │
│   │             │  │             │  │             │  │  addressed  │       │
│   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘       │
│                                                                             │
│   Auth: SQLite replicated via Litestream (tiny, KBs per user)               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component responsibilities

| Component | Language | Runs | Responsibility |
| --- | --- | --- | --- |
| Forge agents | Elixir | Cloud | Stateless API handlers, any agent handles any request |
| mic CLI | Zig | Local | User and agent interface |
| mic-fs | Zig | Local | Virtual filesystem (Phase 2) |
| S3 | - | Cloud | Source of truth: landing log, sessions, trees, blobs |
| SQLite | - | Forge | Auth only (users, tokens, permissions) |

### Why this architecture

Object storage-first:
- S3 is the source of truth, not a cold tier.
- Data inflates from S3 → SSD → RAM as needed.
- Inactive projects cost nearly nothing ($0.023/GB/month).
- Strong consistency since 2020.
- High durability with minimal operational overhead.

Stateless agents:
- No leader election, no partitioning, no Raft.
- Any agent can handle any request.
- Auto-scale based on CPU, scale to zero when idle.
- Agent failure is a non-event (restart only).

S3 conditional writes:
- Landing uses if-match headers for optimistic concurrency.
- S3 provides atomic compare-and-swap.
- No single coordinator bottleneck.
- Multiple landings can race; S3 picks the winner.
- Failed landings retry with backoff.

Binary everywhere:
- All data structures serialize to compact binary.
- Trees, blooms, sessions: all binary.
- Fast to parse, small on disk.
- Zero-copy where possible.

Bloom filter rollups:
- Hierarchical bloom filters cover ranges of landings.
- Conflict checks are O(log n) bloom lookups.
- Avoids O(n) scans over landed sessions.
- Enables 100k+ landings/day.

## Session architecture

Micelio stores all state in S3 as immutable, content-addressed data. A custom NFS server implements copy-on-write semantics to give each session its own isolated view of the project tree.

```
Local developer
  mic CLI -> mic-fs -> NFS server

S3 (source of truth)
  blobs/    content-addressed file content
  trees/    serialized B+ trees
  sessions/ session metadata and tree hashes
```

### S3 storage structure

All mic data is stored in S3 using compact binary formats:

```
s3://mic-{org}/
└── projects/
    └── {project_id}/
        │
        ├── head                         # Current head (48 bytes, binary)
        │   [8 bytes: position (u64)]
        │   [32 bytes: tree_hash]
        │   [8 bytes: hlc_updated]
        │
        ├── landing-log/                 # Append-only landing log
        │   │
        │   ├── 00000000.log             # Positions 0-999 (binary, ~100KB each)
        │   ├── 00001000.log             # Positions 1000-1999
        │   │
        │   └── bloom-index/             # Hierarchical bloom rollups
        │       ├── level-0/             # Individual landings
        │       ├── level-1/             # Bloom of 100 landings merged
        │       ├── level-2/             # Bloom of 10,000 landings merged
        │       └── level-3/             # Bloom of 1M landings merged
        │
        ├── sessions/
        │   └── {session_id}.bin         # Complete session state (binary)
        │
        ├── trees/
        │   └── {hash[0:2]}/
        │       └── {hash}.bin           # Serialized B+ tree (binary)
        │
        └── blobs/
            └── {hash[0:2]}/
                └── {hash}               # Raw blob (zstd compressed)
```

### Blob format

```
Small files (<4MB):
  [4 bytes: magic "MICB"]
  [4 bytes: uncompressed size]
  [zstd compressed content]

Large files (>4MB) are chunked:
  [4 bytes: magic "MICC"]
  [4 bytes: chunk count]
  [N x 32 bytes: chunk hashes]
```

### Copy-on-write and isolation

Each session export points to its own tree hash, so agents do not see unlanded changes from other sessions. Copy-on-write is implemented in the NFS server, not delegated to a specific filesystem. BTRFS is a reference only, not a requirement.

### Consistency guarantees

| Property | How it is achieved |
| --- | --- |
| Isolation | Each session has a dedicated NFS export pointing to its snapshot tree in S3 |
| Immutability | S3 blobs and trees are never modified, only created |
| Reproducibility | Same session ID → same tree → same blobs → same files |
| Atomic landing | S3 conditional writes (if-match / if-none-match) |
| Source of truth | S3 is the single source for blobs, trees, and sessions |

## Scale targets

Micelio is designed for large monorepos and high concurrency:
- Files per project: 1B+.
- Landings per day: 500,000+.
- Concurrent sessions: 100,000+.
- Concurrent agents: 10,000+.

## Monorepo architecture

Monorepos need predictable path lookups and cheap snapshots. Trees are stored as B+ trees in S3 and lookups are O(log n). A session snapshot is just a tree hash, so starting a session is O(1). The data model avoids filesystem dependencies and keeps blob storage immutable and content addressed.

## Storage and cost model

Object storage is the source of truth. S3 stores blobs, trees, sessions, and the landing log. This keeps cost proportional to stored data, not to always-on compute. Auth data lives in a small database, while everything else lives in object storage.

Cost and operations are kept low by:
- Stateless app servers that can scale to zero.
- No coordinator or long-lived stateful services for landing.
- Content addressing and deduplication to reduce storage growth.
- Binary formats for compact storage and faster parsing.

## Conflict detection at scale

Conflict detection uses bloom filters and rollups to avoid scanning all landings. This keeps conflict checks fast as the number of landings grows.

## Performance considerations

| Operation | Complexity | Notes |
| --- | --- | --- |
| File lookup | O(log n) | B+ tree traversal in S3 |
| Session snapshot | O(1) | Record tree hash only |
| Tree diff | O(changes) | Compare tree structures |
| Landing | O(changes log n) | Bloom filter conflict detection |
| Blob storage | O(1) | S3 PUT with content hash |

## Deterministic simulation testing

Inspired by TigerBeetle and FoundationDB, mic uses deterministic simulation to test decades of failures in hours.

What we verify:
- Landing atomicity (all-or-nothing)
- Conflict detection correctness (no false negatives)
- Bloom rollup consistency
- Head monotonicity (position never decreases)
- No data loss under any failure sequence
- HLC causality (if A caused B, HLC(A) < HLC(B))

## Build and validation architecture

The long-term goal is reproducible validation without a separate, opaque CI layer. A controlled environment should be able to produce signed attestations that link a session tree hash to toolchain versions and test outputs. When the environment is reproducible, the policy check becomes a verification of the attestation rather than a rerun of the same work.

### The Nix + S3 integration model

Core insight: agents need local validation they can trust, but the forge needs stateless, scalable execution and caching.

Terminology: the full suite of automated validation (tests, linting, formatting, static analysis, builds, scans) are checks. A check is the same everywhere when it is expressed as a reproducible Nix derivation, so passing locally matches remote execution.

#### Nix's role: environment reproducibility

- flake.nix defines dependencies, build steps, and test environments.
- Local agent validation: `nix develop --command make test`.
- Reproducible anywhere: same Nix derivation = identical environment.
- Content addressing aligns with S3 content-addressable storage.

#### S3's role: stateless persistence and distribution

```
S3 bucket structure:
├── derivations/
│   └── sha256:abc123.drv
├── artifacts/
│   └── sha256:def456/
├── cache/
│   ├── builds/sha256:ghi789
│   ├── tests/sha256:jkl012
│   └── telemetry/sha256:mno345
├── execution-logs/
│   └── sha256:pqr678
└── attestations/
    └── sha256:stu901
```

#### Agent build workflow

```
1. Agent modifies code in mic session
2. Build system generates Nix derivation from changes
3. Check S3 for existing artifact: GET /artifacts/sha256:computed-hash
4. Cache miss → Execute locally: nix-build derivation
5. Cache hit → Skip build, validate locally: nix develop --command make verify
6. Upload results to S3: PUT /artifacts/sha256:new-hash
7. All tests pass → mic land (session includes build attestation)
```

#### Remote execution integration

```
For heavy builds or special capabilities:
├── Agent generates Nix derivation locally
├── Submits to remote execution queue (stored in S3)
├── Remote workers:
│   ├── Fetch derivation from S3
│   ├── Execute in identical Nix environment
│   ├── Upload artifacts back to S3
│   └── Signal completion via S3 event
└── Agent gets notification, validates results locally
```

#### Security and secrets model

```
Capability-based access via S3 policies:
├── Agent identity: arn:aws:iam::account:role/agent-session-abc123
├── Scoped permissions:
│   ├── s3:GetObject on artifacts/* (read builds)
│   ├── s3:PutObject on artifacts/session-abc123/* (write own builds)
│   └── secretsmanager:GetSecretValue for session-scoped secrets
├── Time-bound: role expires with mic session
└── Audit trail: CloudTrail logs every S3/secrets access
```

#### Build cache optimization

```
Content-addressable caching strategy:
├── Input hash: source + dependencies + build script + Nix derivation
├── S3 check: artifacts/sha256:input-hash exists?
├── Cache hit: Download artifact, verify locally with Nix
├── Cache miss: Build locally/remotely, upload to S3
└── Global sharing: all agents benefit from each other's builds
```

#### Stateless forge workers

```
Micelio forge workers (Elixir/Phoenix):
├── No local state: everything in S3
├── Build requests: generate Nix derivations, queue in S3
├── Status queries: check S3 for completion
├── Artifact serving: presigned S3 URLs for downloads
└── Auto-scaling: workers are completely stateless
```

#### Integration with mic sessions

```
Session: "Add payment gateway integration"
├── Goal: Integrate Stripe API safely
├── Build context:
│   ├── Nix derivation: payment-gateway.nix (reproducible env)
│   ├── S3 artifacts: sha256:abc123 (cached build outputs)
│   ├── Test results: sha256:def456 (integration test pass)
│   └── Security attestation: sha256:ghi789 (secrets access logged)
├── Decisions:
│   ├── "Used Stripe test keys for integration tests"
│   └── "All tests pass in identical production environment"
└── Land: Session includes cryptographic proof builds work
```

#### Why this model works

For agents:
- Instant local feedback via Nix.
- Confidence: local success = production success.
- Autonomous: no waiting for CI queues.
- Secure: capability-based secret access.

For organizations:
- Scalable: S3 handles petabytes and millions of artifacts.
- Cost-effective: pay only for storage used, workers auto-scale.
- Auditable: every build, test, and secret access logged.
- Reproducible: bit-for-bit identical builds anywhere.

For the forge:
- Stateless: workers can restart or scale without losing state.
- Global: S3 provides worldwide artifact distribution.
- Reliable: high durability with minimal ops burden.
- Simple: no complex distributed caching layer.

## mic build cache daemon

### Architecture: local daemon + protocol translation

Inspired by Fabrik, mic implements a local daemon that speaks existing build system protocols while providing S3-backed global caching.

```
┌─────────────────────────────────────────────────────────┐
│                    mic daemon                           │
│                  (per-session)                          │
│                                                         │
│ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────┐ │
│ │ Bazel Protocol  │ │ Gradle Protocol │ │Docker Reg.  │ │
│ │ (gRPC Remote    │ │ (HTTP Build     │ │(Layer Cache)│ │
│ │  Cache API)     │ │  Cache API)     │ │             │ │
│ └─────────────────┘ └─────────────────┘ └─────────────┘ │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │            mic Session Engine                       │ │
│ │  • Content-addressable artifact mapping            │ │
│ │  • Session-scoped authentication                   │ │
│ │  • S3 backend with local cache tiers               │ │
│ │  • Automatic protocol detection and routing        │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
                  ┌─────────────────┐
                  │   Micelio S3    │
                  │ (Global Cache)  │
                  └─────────────────┘
```

### Zero-configuration activation

```
# One-time setup
mic activate zsh

# Automatic activation on directory change
cd ~/my-project
# mic detects session context
# starts daemon with session-scoped identity
# exports build tool environment variables
# build commands transparently use cache
```

### Protocol translation examples

Bazel remote cache protocol:

```
export BAZELRC=$HOME/.local/state/mic/sessions/abc123/bazelrc

# Auto-generated bazelrc content:
# build --remote_cache=grpc://localhost:8080
# build --remote_upload_local_results=true

bazel build //...
```

Gradle build cache:

```
export GRADLE_BUILD_CACHE_URL=http://localhost:8080/gradle-cache/
./gradlew build
```

Docker registry protocol:

```
export DOCKER_REGISTRY=localhost:8080

docker build -t myapp .
```

### Session-scoped daemon management

```
mic session start "add-payments"
├── Computes session hash: sha256:abc123...
├── Spawns daemon: ~/.local/state/mic/sessions/abc123/
│   ├── daemon.pid
│   ├── ports.json → {"http": 54321, "grpc": 54322}
│   ├── session_identity → time-bound S3 credentials
│   └── bazelrc → auto-generated build tool configs
├── Session ends → daemon auto-terminates
└── Credentials expire → no lingering access
```

### Multi-toolchain content addressing

```
Source changes hash: sha256:def456...
Build artifacts stored as:
├── s3://forge/artifacts/bazel/def456/binary
├── s3://forge/artifacts/gradle/def456/jar
├── s3://forge/artifacts/docker/def456/layers/
└── s3://forge/artifacts/custom/def456/outputs/
```

Cross-toolchain deduplication:
- Same source hash = shared base artifacts.
- Different toolchains = different artifact paths.
- The daemon handles mapping automatically.

### Advanced cache hierarchy

```
Agent cache lookup order:
1. Local filesystem cache (instant)
2. Local network P2P cache (1-5ms)
3. Regional S3 bucket (10-50ms)
4. Global S3 bucket (50-200ms)
5. Rebuild locally (fallback)
```

### Build system integration matrix

| Build system | Protocol | Configuration | mic integration |
| --- | --- | --- | --- |
| Bazel | gRPC Remote Cache | BAZELRC | Auto-generated bazelrc |
| Gradle | HTTP Build Cache | GRADLE_BUILD_CACHE_URL | Env var export |
| Buck2 | gRPC Remote Cache | Command flags | Alias or wrapper |
| Nx | HTTP Cache API | NX_SELF_HOSTED_REMOTE_CACHE_SERVER | Env var |
| TurboRepo | HTTP API | TURBO_API, TURBO_TOKEN | Auto token + URL |
| Docker | Registry Protocol | DOCKER_REGISTRY | Local registry API |
| sccache | HTTP/S3 Protocol | SCCACHE_ENDPOINT | Compiler cache |
| Custom | HTTP REST | CACHE_URL | Generic cache interface |

### Agent workflow integration

```
Session: "Optimize API performance"
├── Goal: Reduce response time by 50ms
├── Conversation: [agent reasoning about approach]
├── Build context:
│   ├── Cache hits: 95% (Bazel remote cache)
│   ├── Build time: 0.8s (mostly cached)
│   ├── Test time: 2.1s (integration tests)
│   └── Total validation: 2.9s
├── Decisions:
│   ├── "Database connection pooling approach"
│   ├── "All tests pass in <3s - confident change"
│   └── "Performance improvement verified"
└── Land: Session includes build performance metrics
```

### Implementation benefits

For agents:
- Instant feedback via cache hits.
- Zero configuration for build tools.
- Consistent environments across machines.
- Autonomous workflow with no CI queue.

For organizations:
- Shared cache eliminates redundant builds.
- Global consistency for artifacts.
- Session-scoped access and audit trails.
- S3 scales with usage and keeps costs predictable.

For build systems:
- Existing scripts work unchanged.
- Protocol compatibility with standard tools.
- Local daemon avoids network roundtrips.
- Graceful degradation if cache unavailable.

## Session implementation details

### Schema design

Session record:
- goal: what the session aims to accomplish.
- conversation: array of messages (agent/human dialog).
- decisions: array of decision records with reasoning.
- metadata: additional context.
- status: active, landed, or abandoned.
- changes: has-many relationship to SessionChange.

SessionChange record:
- file_path: file that changed.
- change_type: added, modified, or deleted.
- content: inline content for small files (<100KB).
- storage_key: storage reference for large files.
- metadata: file-specific metadata (size, lines changed).

### Storage strategy

- Small files (<100KB) stored inline in content.
- Large files (>=100KB) stored in object storage.
- Storage path pattern: sessions/{session_id}/changes/{file_path}.

### Session lifecycle (gRPC + CLI)

- Start session: SessionService.StartSession.
- Land session: SessionService.LandSession.
- CLI flow:
  - mic session start <organization> <project> <goal>
  - mic session land

### Session changes vs Git commits

| Git commits | Session changes |
| --- | --- |
| Snapshot-based | Context-aware |
| What changed | What changed + why |
| Manual commit messages | Integrated conversation |
| Lost iterations | Preserved reasoning |
| Linear history | Session-based grouping |

## Roadmap highlights

- Session UI that surfaces conversation and decisions.
- Conflict detection and resolution at session boundaries.
- Reproducible validation with cryptographic attestations.
- Developer tooling that keeps agents fast without sacrificing auditability.
