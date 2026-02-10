job "micelio-firecracker-agent" {
  datacenters = ["dc1"]
  type        = "service"

  group "firecracker" {
    count = 1

    network {
      mode = "bridge"
      port "ssh" {
        to = 2222
      }
    }

    task "firecracker-vm" {
      driver = "raw_exec"

      config {
        command = "/usr/bin/firecracker"
        args = [
          "--api-sock",
          "${NOMAD_ALLOC_DIR}/firecracker.sock",
          "--config-file",
          "${NOMAD_ALLOC_DIR}/firecracker.json"
        ]
      }

      template {
        data = <<-EOF
        {
          "boot-source": {
            "kernel_image_path": "/var/lib/micelio/kernel/vmlinux",
            "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
          },
          "drives": [
            {
              "drive_id": "rootfs",
              "path_on_host": "/var/lib/micelio/images/micelio-rootfs.ext4",
              "is_root_device": true,
              "is_read_only": false
            }
          ],
          "machine-config": {
            "vcpu_count": 2,
            "mem_size_mib": 2048,
            "ht_enabled": false
          },
          "network-interfaces": [
            {
              "iface_id": "eth0",
              "host_dev_name": "tap0"
            }
          ]
        }
        EOF
        destination = "${NOMAD_ALLOC_DIR}/firecracker.json"
      }

      resources {
        cpu    = 2000
        memory = 2048
      }
    }
  }
}
