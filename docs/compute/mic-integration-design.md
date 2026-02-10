# mic Integration Design

This document defines how the mic CLI integrates with Micelio's ephemeral
session infrastructure for validation, CI, and agent workloads. It focuses on
clear ownership boundaries between mic, the forge API, and the session manager.

## Goals

- Provide a deterministic workflow for mic to request and use ephemeral sessions.
- Keep mic lightweight by delegating provisioning to the Session Manager API.
- Ensure build/test output and artifacts are captured consistently.
- Support offline/local workflows without requiring session infrastructure.

## Non-Goals

- Redesign mic's local workspace or core storage model.
- Specify provider-specific VM or container details (handled by provisioning).
- Replace existing mic session semantics for landing changes.

## Architecture Overview

Mic delegates ephemeral compute to the Session Manager. Micelio orchestrates the
request, authenticates the caller, and streams results back to the mic client.

```
mic CLI -> Micelio API -> Session Manager -> Runner VM
     ^           |              |              |
     |           |              |              +-- Executes commands
     |           |              +-- Session lifecycle
     |           +-- Auth, policy, audit
     +-- Streams events, output, artifacts
```

## Integration Points

- **Micelio API**: Project-scoped endpoints that translate mic intent into
  session requests and enforce policy (quotas, auth, sandbox rules).
- **Session Manager API**: Receives normalized session requests and returns
  access details. See `docs/compute/session-manager-api.md`.
- **Runner Image**: Standardized image with mic tooling, language runtimes, and
  hooks for streaming output/artifacts.

## Data Flow

1. mic assembles an execution request (purpose, command, workspace ref).
2. Micelio validates access, normalizes, and submits to Session Manager.
3. Session Manager provisions and returns session metadata + access URIs.
4. mic streams logs and results via Micelio's event API.
5. Session is terminated on completion or TTL expiration.

## Session Lifecycle

- **Create**: `POST /v1/sessions` with purpose `validation` or `ci`.
- **Start**: Session Manager reports `running` when runner is ready.
- **Execute**: mic dispatches command(s) over the access channel.
- **Collect**: Output and artifacts are stored in Micelio artifact storage.
- **Terminate**: Explicit termination or TTL expiry triggers cleanup.

## Workspace Mapping

- **Workspace ref**: `project:{id}` or `session:{id}` identifies the mic store.
- **Volumes**:
  - `workspace`: read/write source tree.
  - `cache`: optional dependency or build cache volume.
  - `artifacts`: write-only location for outputs.
- **Checkout strategy**:
  - Prefer cloning mic store snapshot into runner workspace.
  - Optionally mount a read-only snapshot when supported by provider.

## Command Execution Model

- mic sends a command list for the runner to execute in order.
- Each command emits structured events: `status`, `progress`, `output`, `error`.
- Exit codes map to Micelio status (`passed`, `failed`, `canceled`).
- Timeouts are enforced per command and per session.

## Artifact and Log Handling

- stdout/stderr are streamed to the event pipeline.
- Artifacts are uploaded to Micelio storage with content hashes.
- mic receives a manifest describing produced artifacts and metadata.

## Security and Authentication

- mic authenticates to Micelio via short-lived project tokens.
- Micelio authenticates to Session Manager with service credentials.
- Session Manager isolates workloads using sandbox profiles.
- Secrets are injected via ephemeral env vars or mounted secret volumes.

## Failure Modes

- **Provisioning failure**: Session transitions to `failed`, mic retries with
  exponential backoff.
- **Runner crash**: Capture final logs, mark status as `failed`.
- **Network loss**: mic reconnects and resumes log streaming.
- **Policy violation**: Return structured error and halt execution.

## Observability

- Emit metrics for session latency, duration, and exit status.
- Attach correlation IDs across mic, Micelio, and Session Manager logs.
- Persist a summary record per run for audit/review.

## Open Questions

- Should mic support a `--local-only` flag to bypass remote execution entirely?
- What minimum runner image variants are required (language/toolchain matrix)?
- How should mic handle partial artifact uploads if a command fails mid-stream?
