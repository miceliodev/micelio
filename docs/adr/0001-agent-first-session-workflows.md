# 0001 Agent-first session workflows

Date: 2025-09-08

## Status

Accepted

## Context

Micelio is designed around agents making changes on behalf of users. The system needs to
capture the intent and sequence of changes, not just the final diff, while also fitting
into a git-like workflow for contributors.

## Decision

Adopt session-based workflows as the primary unit of change. The `mic` CLI manages
sessions that capture staged edits, metadata, and the rationale for changes before they
are landed. Micelio stores and exposes these sessions, and the web UI surfaces them as
first-class artifacts.

## Consequences

- Agents can attribute changes to sessions with clear intent and provenance.
- Review and audit flows can reason about sessions instead of raw commits.
- Tooling must maintain session metadata throughout landing and browsing workflows.
