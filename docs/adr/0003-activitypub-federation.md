# 0003 ActivityPub federation

Date: 2025-09-08

## Status

Accepted

## Context

Micelio needs to share project and profile activity across instances while remaining
compatible with existing decentralized social networks. Federation must be based on
open standards and work with minimal proprietary infrastructure.

## Decision

Adopt ActivityPub as the federation protocol for projects and profiles. Micelio publishes
ActivityPub-compatible actors and activities, allowing other instances to subscribe to
project updates and user activity.

## Consequences

- Micelio instances can federate with each other and with wider ActivityPub networks.
- Additional maintenance for inbox/outbox handling, signature verification, and caching.
- Public visibility and privacy controls must map cleanly to ActivityPub semantics.
