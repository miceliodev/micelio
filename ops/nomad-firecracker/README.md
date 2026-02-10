# Nomad + Firecracker Prototype

This prototype captures a minimal, repeatable setup for running Firecracker microVMs
under Nomad on a single test host. The goal is to validate scheduling, boot times,
networking, and agent connectivity before scaling.

## Hardware

- 1x bare-metal host with KVM enabled (Intel VT-x/AMD-V)
- 8+ vCPU, 32+ GB RAM, NVMe storage recommended
- Linux kernel with `kvm` and `tun` modules loaded

## Nomad Host Setup

1. Install Nomad and enable the `raw_exec` driver.
2. Install Firecracker + `jailer` and ensure `/dev/kvm` permissions are correct.
3. Create host paths for kernels, rootfs images, and tap interfaces:
   - `/var/lib/micelio/kernel/`
   - `/var/lib/micelio/images/`
4. Create a `tap0` interface and bridge it to the host network (or a dedicated bridge).

## Firecracker Artifacts

- `firecracker-micelio.json` - boot source, drive, and machine config.
- `nomad-firecracker-agent.hcl` - Nomad job spec to launch Firecracker.

## Nomad Job Spec

Use the provided job spec to launch a single VM instance:

```bash
nomad job run ops/nomad-firecracker/nomad-firecracker-agent.hcl
```

## Validation Steps

- Confirm the allocation starts and Firecracker process is running.
- Verify VM boot logs via the serial console (`screen` or `socat`).
- Confirm SSH connectivity to the guest via the forwarded port.
- Capture boot time and steady-state CPU/memory usage.
- Run a simple agent workload to confirm file I/O and network access.

## Results

Record the following after running on test hardware:

- Boot time (cold vs warm start)
- VM resource usage at idle and under load
- Nomad allocation stability (restarts, failures)
- Notes on networking or storage quirks

## Next Steps

- Add a warm pool strategy for faster scheduling.
- Extend the Nomad job with multiple instances and autoscaling.
- Integrate into the session manager provisioning flow.
