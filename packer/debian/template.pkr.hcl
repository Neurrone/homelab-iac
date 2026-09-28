# see these repos
# https://github.com/mabeett/pve-cloud-templates-packer/
# https://github.com/romantomjak/packer-proxmox-template
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

variable "iso_file" {
  type    = string
  default = "local:iso/debian-13.3.0-amd64-netinst.iso"
}
variable "iso_url" {
  type    = string
  default = "https://mirror.sg.gs/debian-cd/current/amd64/iso-cd/debian-13.3.0-amd64-netinst.iso"
}
variable "iso_checksum" {
  type    = string
  default = "sha512:1ada40e4c938528dd8e6b9c88c19b978a0f8e2a6757b9cf634987012d37ec98503ebf3e05acbae9be4c0ec00b52e8852106de1bda93a2399d125facea45400f8"
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
  default = 101
}

variable "vm_name" {
  type    = string
  default = "Debian-13-template"
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

variable "ssh_password" {
  type      = string
  sensitive = true
}

variable "cloudinit_storage_pool" {
  type = string
}

source "proxmox-iso" "debian" {
  # Proxmox connection
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true

  # VM settings
  node                 = var.proxmox_node_name
  vm_id                = var.vm_id
  vm_name              = var.vm_name
  template_name        = var.vm_name
  template_description = "Debian 13 - Built with Packer on ${timestamp()}"

  http_content = {
    "/preseed-auto.cfg" = templatefile("${path.root}/http/preseed.pkrtpl.cfg", {
      ssh_password = var.ssh_password
    })
  }

  # ISO and storage
  boot_iso {
    type             = "scsi"
    iso_file         = "local:iso/debian-13.3.0-amd64-netinst.iso"
    iso_checksum     = var.iso_checksum
    iso_storage_pool = var.iso_storage_pool
    # iso_download_pve = true
    unmount = true
  }
  # boot = "order=virtio0;scsi0;ide1;net0"
  cloud_init              = true
  cloud_init_storage_pool = var.cloudinit_storage_pool

  # Hardware configuration
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
  # vga {
  # type = "serial0"
  # }
  # Boot and SSH configuration
  # https://www.debian.org/releases/stable/amd64/apb.en.html
  boot_command = [
    "<esc><wait>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed-auto.cfg ",
    "console=tty0 console=ttyS0,115200n8 DEBIAN_FRONTEND=text ",
    "<enter>"
  ]
  boot_wait = "5s"
  # problems caused by running in WSL2: the VM isn't able to access the preseed file,
  # hence I have to create a firewall exception and specify the specific port to use
  # New-NetFirewallHyperVRule -Name "PackerHTTP" -DisplayName "Packer HTTP Server" -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP -LocalPorts 10010
  # TODO: find a better way to resolve this
  http_interface = "eth3" # hardcoded to this interface to ensure it works for this machine
  http_port_min  = 10010
  http_port_max  = 10010

  ssh_username = "root" # only used during provisioning, root login disabled after
  ssh_password = var.ssh_password
  ssh_timeout  = "20m"
}

build {
  sources = ["source.proxmox-iso.debian"]

  provisioner "file" {
    destination = "/etc/cloud/cloud.cfg.d/99-packer.cfg"
    source      = "${path.root}/http/cloud.cfg"
  }

  provisioner "shell" {
    inline = [
      "cloud-init status --wait || true",
      # Set DNS defaults in the template image so clones keep stable resolvers
      # without forcing a DHCP renew during cloud-init boot.
      "grep -q '^static domain_name_servers=1.1.1.1 8.8.8.8$' /etc/dhcpcd.conf || printf '\\nstatic domain_name_servers=1.1.1.1 8.8.8.8\\n' >> /etc/dhcpcd.conf",
      "printf 'nameserver 1.1.1.1\\nnameserver 8.8.8.8\\n' >/etc/resolv.conf.head",
      "printf 'nameserver 1.1.1.1\\nnameserver 8.8.8.8\\n' >/etc/resolv.conf",
      "install -d -m 0755 /etc/ssh/sshd_config.d",
      "printf 'PermitRootLogin no\\nPasswordAuthentication no\\nKbdInteractiveAuthentication no\\n' >/etc/ssh/sshd_config.d/99-template-hardening.conf",
      "/usr/sbin/sshd -t",
      "passwd -l root",
      "passwd -S root | awk '{print $2}' | grep -Eq 'L|LK'",
      "cloud-init clean --logs",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",
      "ln -sf /etc/machine-id /var/lib/dbus/machine-id",
      "rm -f /etc/ssh/ssh_host_*",
      "apt-get -y autoremove",
      "apt-get -y clean",
      "rm -rf /tmp/* /var/tmp/*"
    ]
  }
}
