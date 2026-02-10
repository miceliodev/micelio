# GitHub Actions vs Ephemeral VM Cost and Performance Benchmark

This document defines the benchmark plan and reporting template for comparing GitHub Actions to Micelio's self-hosted ephemeral VM runner stack. It focuses on cost per CI minute, throughput, and tail latency for Micelio's workloads.

## Goal

Determine whether the self-hosted ephemeral VM approach delivers lower cost per successful job while meeting or exceeding the performance and reliability of GitHub Actions for Micelio CI and agent runs.

## Scope

In scope:

- CI jobs that represent Micelio workloads (mix compile, mix test, asset build).
- Agent validation runs with sandbox constraints.
- Cost per successful job and per minute.
- Queue time, start latency, and job runtime.

Out of scope:

- Multi-region networking latency.
- Marketplace actions pricing changes beyond the current baseline.
- Non-Linux runner types.

## Benchmark Setup

| Dimension | GitHub Actions | Ephemeral VMs |
| --- | --- | --- |
| Runtime | ubuntu-latest | Firecracker on Nomad |
| Concurrency | 1, 4, 8, 16 | 1, 4, 8, 16 |
| Job Mix | compile, test, assets | compile, test, assets |
| Dataset | Micelio repo at fixed commit | Micelio repo at fixed commit |

## Metrics to Capture

- `queue_time_ms`: time from job request to start.
- `start_latency_ms`: time from start to first command success.
- `job_runtime_ms`: end-to-end runtime.
- `success_rate`: successful runs / total runs.
- `cost_per_minute_usd`: total cost / total runtime minutes.
- `cost_per_success_usd`: total cost / successful runs.

## Cost Model Inputs

Record the inputs used for each benchmark run.

| Input | Description | Example |
| --- | --- | --- |
| gha_price_per_minute_usd | GitHub Actions Linux minute price | 0.008 |
| vm_hourly_cost_usd | Host + infra hourly cost per VM slot | 0.18 |
| vm_slots_per_host | Max concurrent VM slots per host | 16 |
| infra_overhead_usd | Monthly fixed infra cost | 200 |
| power_cost_usd | Monthly power + bandwidth | 100 |

## Cost Calculation

Compute cost per minute for ephemeral VMs as:

```
vm_cost_per_minute_usd = (vm_hourly_cost_usd / 60)
infra_overhead_per_minute_usd = (infra_overhead_usd + power_cost_usd) / total_runtime_minutes
vm_total_cost_per_minute_usd = vm_cost_per_minute_usd + infra_overhead_per_minute_usd
```

Compute cost per success as:

```
cost_per_success_usd = total_cost_usd / successful_runs
```

## Reporting Template

Use this table for the final benchmark summary.

| Runner | Concurrency | p50 runtime (s) | p95 runtime (s) | p95 queue (s) | success rate | cost/min (USD) | cost/success (USD) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GitHub Actions | 4 | TBD | TBD | TBD | TBD | TBD | TBD |
| Ephemeral VMs | 4 | TBD | TBD | TBD | TBD | TBD | TBD |

## Decision Criteria

- Ephemeral VMs are preferred if `cost_per_success_usd` is at least 25% lower than GitHub Actions and p95 runtime is within 10%.
- If p95 queue time exceeds GitHub Actions by more than 30%, add warm pool capacity.
- If success rate drops below 99%, investigate host stability and retry strategy before adoption.

## Next Steps

1. Capture GitHub Actions runs for the job mix at fixed concurrency levels.
2. Run the same workloads on the Firecracker + Nomad stack with identical inputs.
3. Fill in the reporting template with measured values.
4. Store raw JSONL data alongside this document for future comparisons.
