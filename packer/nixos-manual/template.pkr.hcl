packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" {
  type      = string
  sensitive = true
  default   = "https://your-proxmox-ip:8006/api2/json"
}

variable "proxmox_node_name" {
  type = string
}

variable "proxmox_username" {
  type      = string
  sensitive = true
  default   = "your-user@pve"
}

variable "proxmox_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "ssh_password" {
  description = "Temporary bootstrap password used for the live installer and installed bootstrap config."
  type        = string
  sensitive   = true
}

variable "iso_file" {
  type    = string
  default = "local:iso/nixos-minimal-25.11.5960.3aadb7ca9eac-x86_64-linux.iso"
}

variable "iso_url" {
  type    = string
  default = "https://releases.nixos.org/nixos/25.11/nixos-25.11.5960.3aadb7ca9eac/nixos-minimal-25.11.5960.3aadb7ca9eac-x86_64-linux.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:ece127161f8f6c4e8d4bc0fd2bf77f43618f70263eaefcf16e5baafba9f79eb4"
}

variable "iso_storage_pool" {
  type    = string
  default = "local"
}

variable "storage_pool" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "vm_name" {
  type    = string
  default = "NixOS-25.11-template"
}

variable "vm_cores" {
  type    = number
  default = 4
}

variable "vm_memory" {
  type    = number
  default = 4096
}

variable "vm_disk_size" {
  type    = string
  default = "100G"
}

variable "vm_bridge" {
  type    = string
  default = "vmbr0"
}

variable "cloudinit_storage_pool" {
  type = string
}

variable "nixos_state_version" {
  description = "NixOS system.stateVersion for the installed template."
  type        = string
  default     = "25.11"
}

source "proxmox-iso" "nixos" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true

  node                 = var.proxmox_node_name
  vm_id                = var.vm_id
  vm_name              = var.vm_name
  template_name        = var.vm_name
  template_description = "NixOS ${var.nixos_state_version} (manual installer) - Built with Packer on ${timestamp()}"

  http_content = {
    "/nixos/bootstrap-installer.sh" = templatefile("${path.root}/http/bootstrap-installer.pkrtpl.sh", {
      ssh_password = var.ssh_password
    })
  }

  boot_iso {
    type             = "scsi"
    iso_file         = var.iso_file
    iso_checksum     = var.iso_checksum
    iso_storage_pool = var.iso_storage_pool
    # iso_download_pve = true
    unmount = true
  }

  cloud_init              = true
  cloud_init_storage_pool = var.cloudinit_storage_pool

  qemu_agent      = true
  scsi_controller = "virtio-scsi-pci"

  disks {
    type         = "virtio"
    storage_pool = var.storage_pool
    disk_size    = var.vm_disk_size
    discard      = true
    format       = "raw"
  }

  cores  = var.vm_cores
  memory = var.vm_memory

  network_adapters {
    model    = "virtio"
    bridge   = var.vm_bridge
    firewall = false
  }

  serials = [
    "socket",
  ]

  boot_command = [
    # Edit the default boot entry and append a serial console so Proxmox
    # `qm terminal` (serial0) receives live-installer output.
    "<tab><wait1s>",
    " console=tty0 console=ttyS0,115200n8",
    "<enter>",
    "<wait7s>",
    "<enter><wait2s>",
    "curl -fsSL http://{{ .HTTPIP }}:{{ .HTTPPort }}/nixos/bootstrap-installer.sh -o /tmp/bootstrap-installer.sh && sudo -n systemd-run --unit=packer-bootstrap --wait --collect -p StandardInput=null -p StandardOutput=tty -p StandardError=tty -p TTYPath=/dev/ttyS0 /run/current-system/sw/bin/bash -eu /tmp/bootstrap-installer.sh",
    "<enter>",
  ]
  boot_wait = "5s"

  # problems caused by running in WSL2: the VM isn't able to access the HTTP content,
  # hence a fixed port/interface is used
  http_interface = "eth3"
  http_port_min  = 10010
  http_port_max  = 10010

  # Connect first to the live installer, then reconnect to the installed bootstrap system.
  ssh_username = "nixos"
  ssh_password = var.ssh_password
  ssh_timeout  = "20m"
}

build {
  sources = ["source.proxmox-iso.nixos"]

  provisioner "file" {
    source      = "${path.root}/nix"
    destination = "/tmp"
  }

  provisioner "shell" {
    execute_command   = "chmod +x {{ .Path }}; {{ .Vars }} sudo -n {{ .Path }}"
    expect_disconnect = true
    environment_vars = [
      "BOOTSTRAP_PASSWORD=${var.ssh_password}",
      "NIXOS_STATE_VERSION=${var.nixos_state_version}",
    ]
    script = "${path.root}/scripts/install-nixos.sh"
  }

  provisioner "shell" {
    execute_command     = "chmod +x {{ .Path }}; {{ .Vars }} sudo -n {{ .Path }}"
    expect_disconnect   = true
    start_retry_timeout = "20m"
    script = "${path.root}/scripts/finalize-template.sh"
  }
}
