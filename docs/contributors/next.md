# What's Next

This document tracks upcoming work, implementation status, and ideas for Micelio.

---

## Forge (Elixir/Phoenix)

### Completed

- [x] **SKILL.md** - Created at `priv/static/SKILL.md` and served at `/SKILL.md`
- [x] **REST API for agents** - RESTful API endpoints for AI agents to interact with Micelio
- [x] **Activity graph** - GitHub-style contribution/activity visualization
- [x] **OpenGraph utilities** - Helper functions for OG meta tags and dynamic OG images
- [x] **Gravatar integration** - Default avatar for users based on email
- [x] **Account avatar customization** - Allow users to upload and change their avatar

### Implementation Plan

The forge uses stateless agents with S3 as the source of truth, inspired by Turbopuffer, WarpStream, and Calvin. See [design.md](design.md) for full architecture details.

#### Phase 1: Auth Database (SQLite)

Store users, tokens, and permissions in SQLite.

- [x] Add `ecto_sqlite3` dependency and configure SQLite
- [x] Implement authentication (OAuth with Boruta, device auth, gRPC auth)
- [x] Implement authorization contexts (`Micelio.Authorization`)

#### Phase 2: S3 Storage Layer (Binary)

Read/write mic data to S3 using binary formats.

- [x] Storage abstraction with local + S3 backends
- [x] Implement `Micelio.Hif.Binary` serialization (head, landing, session summary, path index, rollup checkpoint)

#### Phase 3: Session CRUD

- [x] Session CRUD (database + REST endpoints)
- [x] Basic landing endpoint (non-conditional)

#### Phase 4: Coordinator-Free Landing

Landing via S3 conditional writes, no coordinator process.

- [x] Coordinator-free landing with conditional writes (`put_if_match`, `put_if_none_match`)
- [x] Bloom filter rollups for O(log n) conflict detection (3 levels: 100, 10K, 1M)

#### Phase 5: API Endpoints

- [x] gRPC API (projects service)
- [x] Session gRPC API (start, land, get, list with path filtering)

#### Phase 6: Tiered Caching

Fast reads via multi-tier caching (RAM -> SSD -> CDN -> S3).

---

## mic (Zig)

### Completed

- [x] Project initialized with Zig 0.15
- [x] `core/hash.zig` - Blake3 hashing
- [x] `core/bloom.zig` - Bloom filters for conflict detection
- [x] `core/hlc.zig` - Hybrid Logical Clock for distributed timestamps
- [x] `core/tree.zig` - B+ tree for directory structures
- [x] Binary serialization for all types (`mic/src/core/serialize.zig`)
- [x] Integration tests - End-to-end workflow tests
- [x] gRPC client with TLS support
- [x] Basic CLI commands (auth, checkout, status, land)
- [x] Clone command with git-like semantics
- [x] Token refresh with file-system locking
- [x] Conflict resolution with server-side detection
- [x] Error recovery and rollback (atomic writes, backups, retry)
- [x] `mic log` - List landed sessions
- [x] `mic log --path` - Sessions touching path
- [x] `mic diff` - Diff between two states
- [x] `mic goto @N` - View tree at position N

### Phase 4: Virtual Filesystem (mic-fs)

- [ ] NFS v3 server implementation
- [ ] Session overlay for local changes
- [ ] `mic mount` / `mic unmount` commands
- [ ] Prefetch on directory open

### Phase 5: Scale

- [ ] Bloom filter rollup background job
- [ ] Epoch batching mode (high throughput)
- [ ] CDN integration for blobs
- [ ] Delta compression

---

## Architecture Notes

### Tree Implementation

The current `tree.zig` uses a sorted ArrayList for simplicity:
- O(log n) lookups via binary search
- O(n) insertions due to re-sorting
- Suitable for small to medium trees (< 10K entries)

For large-scale repositories (100K+ files), a proper B-tree or prolly tree with probabilistic chunking boundaries would be needed. Deferred to Phase 5.

### gRPC Client

The mic CLI uses vendored gRPC C core `v1.76.0` (TLS required) via `mic/vendor/grpc`.

---

## Ideas

These are exploratory ideas for future consideration:

### Forge Features
- Fediverse integration
- Rate limiting when not authenticated
- Public vs private repositories
- OAuth2 dynamic registration for MCP clients
- OpenAPISpex setup
- PR stacking (like GitHub is working on)
- Store issues/PRs in the repository itself for portability
- GitHub Pages-like static site hosting
- Design tags/releases as first-class mic objects (session-linked, immutable)

### Security
- Sanitize fetch account & repository queries to prevent injection
- Define project boundaries using Boundary library
- Admin declaration and authorization

### Scaling
- Track file-system or git operations per account/repo for sharding decisions
- Decide on SQLite vs Postgres vs MySQL
- Explore Ceph for horizontal storage scaling

### Desktop/CLI
- Desktop app built with Zig (like Zed with Rust)
- Kamal replacement in pure Zig
- Static site deployment tool

### Research
- How does SourceHut handle issues and mailing lists?
- Can marketing pages be included and removed at compile-time?
