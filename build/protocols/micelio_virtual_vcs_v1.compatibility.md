# micelio_virtual_vcs_v1 Compatibility Mapping

## Mapping to Existing gRPC Services

This document is the compatibility bridge for Step 1. It keeps legacy clients and new
Session-native clients aligned during rollout.

| Legacy RPC | New RPC | Notes |
|---|---|---|
| `micelio.sessions.v1.SessionService.StartSession` | `micelio.virtual.v1.VersioningService.OpenSession` | Same intent, new explicit base position and attribution model |
| `micelio.sessions.v1.SessionService.GetSession` | `micelio.virtual.v1.VersioningService.GetSession` | Returns richer context in new `SessionInfo` |
| `micelio.sessions.v1.SessionService.LandSession` | `micelio.virtual.v1.VersioningService.LandSession` | Adds explicit `epoch` and `force` progression fields |
| `micelio.sessions.v1.SessionService.ListSessions` | *N/A in v1* | Compatibility window: existing list endpoint remains active for v1 launch |
| `micelio.sessions.v1.SessionService.CaptureSessionEvent` | `micelio.virtual.v1.VersioningService.AppendSessionConversation` | Event stream is preserved through event append shape |
| `micelio.content.v1.ContentService.GetTree` | `micelio.virtual.v1.ContentService.GetTree` | Preserves position/tree lookup, adds `path_prefix` and `tree_hash` for sparse reads |
| `micelio.content.v1.ContentService.GetPath` | `micelio.virtual.v1.ContentService.GetPath` | Position-first reads with no local checkout required |
| `micelio.content.v1.ContentService.GetBlob` | `micelio.virtual.v1.ContentService.GetBlob` | Blob reads remain content-hash based |
| `micelio.content.v1.ContentService.Blame` | `micelio.virtual.v1.ContentService.Blame` | Path and line attribution enriched with session metadata |
| `micelio.repositories.v1.GetRepositoryHead` | `micelio.virtual.v1.VersioningService.GetRepositoryHead` | Head includes ETag and position for CAS safety |

## New Surface Area (Additive Only)

- `micelio.virtual.v1.SearchService.QueryText` introduces repository-scale query.
- `micelio.virtual.v1.GetHeadAt` exposes historical positions.
- `SessionInfo.attribution` is expanded for agent workflow metadata.

## Rollout Rule

- Legacy services continue to operate unchanged while clients migrate.
- New fields are additive and must remain optional/ignored for older clients.
- Search and head-at helpers are gated behind feature flags in CLI until service availability is confirmed.
