# Packer Firecracker Image Builder (PoC)

This proof-of-concept uses HashiCorp Packer to build a minimal Linux rootfs image
suitable for Firecracker microVMs. It focuses on repeatability and a clean handoff
into the Nomad + Firecracker prototype.

## Prerequisites

- Packer v1.9+
- QEMU with KVM enabled on the host
- 10+ GB free disk space

## Files

- `firecracker.pkr.hcl` - Packer template for building the image.
- `http/user-data` - Ubuntu autoinstall cloud-init config.
- `http/meta-data` - Cloud-init metadata.
- `scripts/bootstrap.sh` - Post-install provisioning for Micelio needs.

## Build

```bash
packer init ops/packer-firecracker/firecracker.pkr.hcl
packer build \
  -var 'iso_url=https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso' \
  -var 'iso_checksum=sha256:45f873de9f93b26a84f3b0f7d07a7a1f8b6fd32fb08f5372a79f0dd8b8ab44dd' \
  ops/packer-firecracker/firecracker.pkr.hcl
```

Packer outputs a raw disk image under `ops/packer-firecracker/output/`.
Copy the resulting rootfs into the Firecracker image store (for example
`/var/lib/micelio/images/`).

## Validation Checklist

- Boot the image using `ops/nomad-firecracker/firecracker-micelio.json`.
- Confirm SSH access with the `micelio` user.
- Run a lightweight agent workload (git clone + read/write + curl).

## Notes

- The autoinstall config enables password auth for the PoC; harden before use.
- Update `scripts/bootstrap.sh` for production packages and hardening.
