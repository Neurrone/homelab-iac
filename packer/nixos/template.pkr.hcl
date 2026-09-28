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
  description = "Temporary bootstrap password used for the NixOS installer 'nixos' user and the installed bootstrap config."
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
  type    = number
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

variable "nixos_anywhere_flake_attr_bootstrap" {
  description = "Flake attr used by nixos-anywhere for the temporary bootstrap config."
  type        = string
  default     = "nixos-template-bootstrap"
}

variable "nixos_anywhere_flake_attr_final" {
  description = "Flake attr used by nixos-rebuild for the final template config."
  type        = string
  default     = "nixos-template-final"
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
  template_description = "NixOS ${var.nixos_state_version} - Built with Packer on ${timestamp()}"

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

  # Keep VGA enabled for easier debugging if the boot_command timing needs tuning.
  vga {
    type = "std"
  }

  # The minimal ISO generally lands in a root shell on tty1. If the timing is off on
  # your host/ISO revision, increase waits here first.
  boot_command = [
    "<wait10s>",
    "<enter><wait2s>",
    "curl -fsSL http://{{ .HTTPIP }}:{{ .HTTPPort }}/nixos/bootstrap-installer.sh | bash -eux",
    "<enter>",
  ]
  boot_wait = "10s"

  # problems caused by running in WSL2: the VM isn't able to access the HTTP content,
  # hence a fixed port/interface is used
  http_interface = "eth3"
  http_port_min  = 10010
  http_port_max  = 10010

  # Connect first to the live installer, then to the installed bootstrap system using the
  # same temporary credentials. Packer discovers the guest IP, and shell-local reuses it
  # via build.Host/build.Port/build.User.
  ssh_username = "nixos"
  ssh_password = var.ssh_password
  ssh_timeout  = "45m"
}

build {
  sources = ["source.proxmox-iso.nixos"]

  provisioner "shell-local" {
    environment_vars = [
      "BOOTSTRAP_PASSWORD=${var.ssh_password}",
      "INSTALLER_SSH_HOST=${build.Host}",
      "INSTALLER_SSH_PORT=${build.Port}",
      "INSTALLER_SSH_USER=${build.User}",
      "NIXOS_ANYWHERE_FLAKE_ATTR_BOOTSTRAP=${var.nixos_anywhere_flake_attr_bootstrap}",
      "NIXOS_NIX_CONFIG_SRC=${abspath(path.root)}/nix",
      "NIX_CONFIG=experimental-features = nix-command flakes",
    ]
    inline = [
      "command -v nix >/dev/null",
      "command -v openssl >/dev/null",
      "command -v ssh-keyscan >/dev/null",
      "tmpdir=$(mktemp -d)",
      "trap 'rm -rf \"$tmpdir\"' EXIT",
      "cp -R \"$NIXOS_NIX_CONFIG_SRC\"/. \"$tmpdir\"/",
      "mkdir -p \"$tmpdir/generated\"",
      "pw_hash=$(printf '%s' \"$BOOTSTRAP_PASSWORD\" | openssl passwd -6 -stdin)",
      "cat >\"$tmpdir/generated/bootstrap-secrets.nix\" <<EOF\n{ ... }: {\n  users.users.nixos.hashedPassword = \"$pw_hash\";\n}\nEOF",
      "home_tmp=\"$tmpdir/home\"",
      "mkdir -p \"$home_tmp/.ssh\"",
      "ssh-keyscan -p \"$INSTALLER_SSH_PORT\" -H \"$INSTALLER_SSH_HOST\" >\"$home_tmp/.ssh/known_hosts\" 2>/dev/null",
      "export HOME=\"$home_tmp\"",
      "export SSHPASS=\"$BOOTSTRAP_PASSWORD\"",
      "nix run github:nix-community/nixos-anywhere -- --env-password --ssh-port \"$INSTALLER_SSH_PORT\" --flake \"$tmpdir#$NIXOS_ANYWHERE_FLAKE_ATTR_BOOTSTRAP\" --target-host \"$INSTALLER_SSH_USER@$INSTALLER_SSH_HOST\"",
    ]
  }

  provisioner "file" {
    source      = "${path.root}/nix"
    destination = "/tmp"
  }

  provisioner "shell" {
    # Packer connects as the temporary nixos user declared in the bootstrap flake config.
    execute_command   = "chmod +x {{ .Path }}; {{ .Vars }} sudo -n {{ .Path }}"
    expect_disconnect = true
    inline = [
      "nixos-rebuild switch --flake /tmp/nix#${var.nixos_anywhere_flake_attr_final}",
      "/run/current-system/sw/bin/sshd -t",
      "userdel -f -r nixos || true",
      "cloud-init clean --logs || true",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",
      "ln -sf /etc/machine-id /var/lib/dbus/machine-id",
      "rm -f /etc/ssh/ssh_host_*",
      "nix-collect-garbage -d || true",
      "journalctl --rotate || true",
      "journalctl --vacuum-time=1s || true",
      "rm -rf /tmp/* /var/tmp/*",
      "systemctl poweroff",
    ]
  }
}
