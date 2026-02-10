# Session Manager API

This document defines the contract for the Session Manager that provisions,
tracks, and terminates ephemeral agent workspaces. It is written for internal
services (agent runner, VM orchestrator, and UI) to stay consistent regardless
of the underlying VM provider.

## Overview

The Session Manager owns the lifecycle of an isolated execution environment. It
accepts a normalized session request, provisions compute, and returns a session
record with access details and lifecycle timestamps.

## Transport and Versioning

- Transport: HTTP + JSON (gRPC is allowed as long as the payloads match).
- Base path: `/v1/sessions`
- Versioning: URL versioning (`/v1`) with additive changes only.

## Authentication

- Service-to-service bearer token in the `Authorization` header.
- Tokens map to a service account with scoped permissions.

## Endpoints

`POST /v1/sessions`
Create a session from a `session_request`.

`GET /v1/sessions/{id}`
Fetch a session by id.

`GET /v1/sessions`
List sessions with optional filters (`state`, `purpose`, `workspace_ref`).

`POST /v1/sessions/{id}/terminate`
Terminate a session and release resources.

`POST /v1/sessions/{id}/extend`
Extend TTL (body: `{"ttl_seconds": 1800}`).

`POST /v1/sessions/{id}/heartbeat`
Signal that the session is still in use.

## Session Schema

```json
{
  "id": "sess_123",
  "state": "running",
  "request": { "..." : "session_request" },
  "instance": {
    "ref": "provider-specific",
    "provider": "firecracker",
    "status": {
      "state": "running",
      "hostname": "vm-123",
      "ip_address": "10.0.0.5",
      "metadata": {}
    },
    "metadata": {}
  },
  "access": [
    { "type": "ssh", "uri": "ssh://agent@10.0.0.5:2222", "metadata": {} }
  ],
  "created_at": "2025-01-01T00:00:00Z",
  "started_at": "2025-01-01T00:00:10Z",
  "expires_at": "2025-01-01T02:00:00Z",
  "metadata": {}
}
```

Session states: `queued`, `starting`, `running`, `stopping`, `stopped`,
`failed`, `expired`.

Access types: `ssh`, `http`, `grpc`, `websocket`.

## Session Request Schema

```json
{
  "purpose": "validation",
  "workspace_ref": "project:123",
  "command": ["mix", "test"],
  "env": { "MIX_ENV": "test" },
  "working_dir": "/workspace",
  "ttl_seconds": 3600,
  "metadata": {},
  "plan": { "...": "provisioning_plan" }
}
```

`purpose` must be one of: `agent`, `validation`, `review`, `ci`, `debug`.

## Provisioning Plan Schema

```json
{
  "provider": "firecracker",
  "image": "micelio/agent-runner:latest",
  "cpu_cores": 2,
  "memory_mb": 2048,
  "disk_gb": 20,
  "network": "default",
  "ttl_seconds": 3600,
  "sandbox": { "...": "sandbox_profile" },
  "volumes": [ { "...": "volume_mount" } ]
}
```

## Sandbox Profile Schema

```json
{
  "isolation": "microvm",
  "network_policy": "egress-only",
  "filesystem_policy": "workspace-rw",
  "run_as_user": "agent",
  "seccomp_profile": "default",
  "capabilities": [],
  "allowlist_hosts": [],
  "max_processes": 256,
  "max_open_files": 1024
}
```

## Volume Mount Schema

```json
{
  "name": "workspace",
  "source": "volume:workspace-123",
  "target": "/workspace",
  "access": "rw",
  "type": "volume"
}
```

## State Transitions

- `queued` -> `starting` -> `running`
- `running` -> `stopping` -> `stopped`
- `starting`/`running` -> `failed`
- `running` -> `expired` (TTL reached)

## Errors

Errors return JSON in the form:

```json
{
  "error": {
    "code": "invalid_request",
    "message": "working_dir must be an absolute path",
    "retryable": false,
    "metadata": {}
  }
}
```

Common error codes: `invalid_request`, `not_found`, `conflict`, `rate_limited`,
`provider_unavailable`, `timeout`.

## Idempotency

`POST /v1/sessions` accepts `Idempotency-Key` to prevent duplicate sessions on
retry. If the same key is re-used within the TTL window, the same session is
returned.

## Observability

- Emit metrics: `session.create`, `session.start`, `session.failed`,
  `session.terminated`, and `session.duration`.
- Include `session_id` and `workspace_ref` tags for tracing.
