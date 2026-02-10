# 0004 Sandboxed agent execution

Date: 2026-01-20

## Status

Accepted

## Context

Micelio runs agent-driven workloads that execute untrusted code. The platform needs a
consistent sandbox model that can be enforced across providers while still allowing
project-specific customization (network access, filesystem exposure, and runtime
limits). We also want a single configuration model that is easy to validate and pass to
providers.

## Decision

Introduce a sandbox profile as part of agent provisioning plans. The profile defines
isolation level, network policy, filesystem policy, and runtime limits with secure
defaults:

- **Isolation**: microVM by default (`firecracker` or `cloud-hypervisor` providers),
  with explicit alternatives for container or process sandboxing.
- **Network policy**: default to egress-only; allow `none`, `restricted` (allowlist
  required), and `full` for trusted workloads.
- **Filesystem policy**: default to immutable root with a writable workspace volume.
- **Identity**: enforce non-root execution inside the sandbox.
- **Limits**: set process and file descriptor caps in addition to CPU/memory/disk
  limits from the provisioning plan.

The sandbox profile is validated at plan construction time and normalized into provider
requests, so every provider receives a consistent sandbox specification.

## Consequences

- Agent execution always carries an explicit sandbox policy, even when callers omit
  configuration (secure defaults apply).
- Providers can map the policy to platform-specific controls (seccomp/apparmor, VM
  jailer settings, or container runtime policies).
- Future UI work can expose the profile fields without reworking provisioning logic.
