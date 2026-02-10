# 0002 Tiered storage caching

Date: 2025-09-08

## Status

Accepted

## Context

Micelio serves repository content to web and API clients with high read frequency. Reads
need to stay fast while keeping storage costs under control. The platform also targets
self-hosted deployments where infra resources vary widely.

## Decision

Implement a tiered caching strategy: hot objects are kept in memory, warm objects on SSD,
then served via CDN, with S3-compatible object storage as the source of truth. The storage
layer promotes or demotes objects based on access patterns and provides unified APIs for
read and write access.

## Consequences

- Read latency is minimized for common paths while keeping storage costs lower.
- More complexity in cache invalidation and promotion logic.
- Storage backends must maintain compatibility across tiers and deployments.
