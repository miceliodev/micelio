packer {
  required_plugins {
    qemu = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "iso_url" {
  type        = string
  description = "Ubuntu server ISO URL."
}

variable "iso_checksum" {
  type        = string
  description = "Checksum for the ISO (format: sha256:...)."
}

variable "ssh_username" {
  type        = string
  description = "SSH username for the build user."
  default     = "micelio"
}

variable "ssh_password" {
  type        = string
  description = "SSH password for the build user."
  default     = "micelio"
}

variable "disk_size" {
  type        = string
  description = "Disk size in MB."
  default     = "8192"
}

variable "output_directory" {
  type        = string
  description = "Directory for packer build output."
  default     = "ops/packer-firecracker/output"
}

variable "headless" {
  type        = bool
  description = "Run QEMU in headless mode."
  default     = true
}

source "qemu" "firecracker" {
  accelerator      = "kvm"
  boot_wait        = "5s"
  disk_size        = var.disk_size
  format           = "raw"
  headless         = var.headless
  http_directory   = "${path.root}/http"
  iso_checksum     = var.iso_checksum
  iso_url          = var.iso_url
  output_directory = var.output_directory
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  ssh_password     = var.ssh_password
  ssh_timeout      = "30m"
  ssh_username     = var.ssh_username
  vm_name          = "micelio-firecracker"

  boot_command = [
    "<esc><wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<enter>",
    "initrd /casper/initrd<enter>",
    "boot<enter>"
  ]
}

build {
  sources = ["source.qemu.firecracker"]

  provisioner "shell" {
    script = "${path.root}/scripts/bootstrap.sh"
  }
}
