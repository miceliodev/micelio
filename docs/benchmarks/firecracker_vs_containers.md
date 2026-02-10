# Firecracker vs Containers Benchmark Plan

This document captures the benchmark plan and acceptance criteria for comparing Firecracker microVMs against OCI containers (runc) for Micelio's ephemeral environments.

## Goal

Quantify the tradeoffs between Firecracker microVMs and containers in terms of startup latency, steady-state performance, isolation cost, and operational overhead for the Micelio agent/CI workload.

## Scope

The benchmark focuses on:

- Cold start time (from request to ready state)
- Warm start time (pre-warmed VM or container pool)
- CPU throughput under mixed workloads
- Memory overhead (RSS, kernel usage, cache behavior)
- Disk and network I/O throughput
- Multi-tenant density (concurrency before saturation)

Out of scope: cloud provider-specific pricing and multi-region networking behavior.

## Workload Matrix

Each workload should be run in both Firecracker and container environments under identical host conditions.

| Workload | Description | Success Criteria |
| --- | --- | --- |
| Boot | Start-to-ready for a minimal image | < 1s warm, < 3s cold target |
| CPU | Run `mix test` on a medium repo | Comparable throughput, <= 15% delta |
| I/O | Archive extract + checksum on 1-2 GB data | Within 20% throughput delta |
| Network | Fetch 100 MB artifact from local cache | Within 10% throughput delta |
| Mixed | CI job: compile + test + asset build | No perf cliff, predictable tail latency |

## Benchmark Harness

Use a single benchmark harness to avoid differing scripts between runtimes.

1. **Image Baselines**
   - Firecracker: minimal rootfs with required toolchain.
   - Containers: OCI image with identical OS packages and toolchain.
2. **Start Signal**
   - Record timestamp at `create` request.
   - Record timestamp when SSH/exec is available and first command succeeds.
3. **Data Collection**
   - System metrics: CPU, RAM, disk IO, network IO.
   - Runtime metrics: start latency p50/p95/p99.
   - Host impact: total concurrent jobs before saturation.

## Environment Controls

- Run on a single host class (fixed CPU model, RAM, disk).
- Disable background workloads that introduce noise.
- Pin CPU governor to `performance` mode.
- Repeat each workload 30 times; discard the first run as warm-up.

## Metrics to Capture

- `start_latency_ms`: p50/p95/p99
- `cpu_seconds`: per workload
- `rss_mb`: peak + steady
- `io_read_mb_s` / `io_write_mb_s`
- `net_rx_mb_s` / `net_tx_mb_s`
- `max_concurrency`: steady-state success count before queueing

## Data Recording Format

Store results in a JSONL file to feed comparisons and graphs later.

```json
{"runtime":"firecracker","workload":"boot","run":1,"start_latency_ms":512,"rss_mb":248}
```

## Analysis & Decision Criteria

A Firecracker baseline should be adopted if:

- Startup latency remains within 2x of containers for warm pool scenarios.
- Memory overhead is <= 2x container RSS for typical workloads.
- Isolation benefits outweigh any throughput delta for security-sensitive jobs.

Otherwise, containers remain the default and Firecracker is reserved for untrusted workloads only.

## Open Questions

- Can a warm Firecracker pool meet sub-500ms start times?
- What is the per-VM memory floor on our target hardware?
- How much operational overhead is added by image building and registry sync?

## Next Steps

1. Implement a reproducible benchmark harness (Elixir or shell + JSONL output).
2. Build baseline Firecracker and container images with identical toolchains.
3. Run benchmarks on the planned hardware pool and record raw data.
4. Summarize results and update this document with measured numbers.
