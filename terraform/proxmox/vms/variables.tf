variable "proxmox_sops_file" {
  description = "Path to encrypted SOPS file containing proxmox_endpoint, auth (proxmox_api_token or proxmox_username/proxmox_password), and per-VM cloud-init credentials under top-level key `vms`"
  type        = string

  validation {
    condition     = trimspace(var.proxmox_sops_file) != ""
    error_message = "proxmox_sops_file must not be empty."
  }
}

variable "state_encryption_passphrase" {
  description = "Passphrase for OpenTofu PBKDF2 state encryption. Set via TF_VAR_state_encryption_passphrase (for example via sops exec-env)."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Set true if Proxmox TLS cert is self-signed"
  type        = bool
  default     = true
}

variable "proxmox_node_name" {
  description = "Target Proxmox node where VMs are created"
  type        = string
}

variable "template_vm_id" {
  description = "VMID of the Packer-built Proxmox template"
  type        = number
}

variable "storage_pool" {
  description = "Datastore used for VM root disks"
  type        = string
}

variable "cloudinit_storage_pool" {
  description = "Datastore used for Cloud-Init disks"
  type        = string
}

variable "root_disk_interface" {
  description = "Primary/root disk interface to manage (match your template root disk slot, e.g. virtio0 or scsi0)"
  type        = string
  default     = "virtio0"
}

variable "default_network_bridge" {
  description = "Default Proxmox bridge for VM NICs"
  type        = string
  default     = "vmbr0"
}

variable "vms" {
  description = "Map of VMs keyed by VM name. Add entries here to create multiple VMs."
  type = map(object({
    vm_id                = number
    ssh_public_key_paths = list(string)
    cpu_cores            = optional(number)
    memory_min_mb        = optional(number)
    memory_max_mb        = optional(number)
    disk_size_gb         = optional(number)
    network_bridge       = optional(string)
    ipv4_address         = optional(string)
    ipv4_gateway         = optional(string)
    start_on_create      = optional(bool)
  }))

  validation {
    condition = alltrue([
      for _, vm in var.vms : length(compact(vm.ssh_public_key_paths)) > 0
    ])
    error_message = "Each VM must define at least one SSH public key in ssh_public_key_paths."
  }

  validation {
    condition = alltrue([
      for _, vm in var.vms : (
        try(vm.ipv4_address, null) == null ||
        lower(trimspace(vm.ipv4_address)) == "dhcp" ||
        can(regex(
          "^(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(?:\\.(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])){3}/(?:[0-9]|[1-2][0-9]|3[0-2])$",
          trimspace(vm.ipv4_address)
        ))
      )
    ])
    error_message = "Each ipv4_address must be either \"dhcp\" or CIDR format like \"192.168.2.170/24\"."
  }

  validation {
    condition = alltrue([
      for _, vm in var.vms : (
        try(vm.ipv4_gateway, null) == null ||
        can(regex(
          "^(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(?:\\.(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])){3}$",
          trimspace(vm.ipv4_gateway)
        ))
      )
    ])
    error_message = "Each ipv4_gateway must be a valid IPv4 address like \"192.168.2.1\"."
  }

  validation {
    condition = alltrue([
      for _, vm in var.vms : (
        try(vm.ipv4_gateway, null) == null ||
        (
          try(vm.ipv4_address, null) != null &&
          lower(trimspace(vm.ipv4_address)) != "dhcp"
        )
      )
    ])
    error_message = "When ipv4_gateway is set, ipv4_address must also be set to a static CIDR value (not dhcp)."
  }

}
