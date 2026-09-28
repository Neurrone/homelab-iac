terraform {
  required_version = ">= 1.7.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "~> 0.98.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.4"
    }
  }

  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_encryption_passphrase
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    state {
      method   = method.aes_gcm.state
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}

data "sops_file" "proxmox" {
  source_file = var.proxmox_sops_file
}

locals {
  sops_config = jsondecode(data.sops_file.proxmox.raw)

  proxmox_endpoint  = lookup(local.sops_config, "proxmox_endpoint", null)
  proxmox_api_token = lookup(local.sops_config, "proxmox_api_token", null)
  proxmox_username  = lookup(local.sops_config, "proxmox_username", null)
  proxmox_password  = lookup(local.sops_config, "proxmox_password", null)

  has_proxmox_endpoint = local.proxmox_endpoint != null && trimspace(local.proxmox_endpoint) != ""
  has_api_token        = local.proxmox_api_token != null && trimspace(local.proxmox_api_token) != ""
  has_username_password = (
    local.proxmox_username != null &&
    trimspace(local.proxmox_username) != "" &&
    local.proxmox_password != null &&
    trimspace(local.proxmox_password) != ""
  )
}

provider "proxmox" {
  endpoint  = local.proxmox_endpoint
  api_token = local.proxmox_api_token
  username  = local.proxmox_username
  password  = local.proxmox_password
  insecure  = var.proxmox_insecure
}

check "proxmox_credentials" {
  assert {
    condition     = local.has_proxmox_endpoint
    error_message = "proxmox_sops_file must contain proxmox_endpoint."
  }

  assert {
    condition     = local.has_api_token != local.has_username_password
    error_message = "proxmox_sops_file must contain exactly one auth method: proxmox_api_token or proxmox_username+proxmox_password."
  }
}

check "vm_memory_ballooning" {
  assert {
    condition = alltrue([
      for _, vm in local.resolved_vms :
      vm.memory_min_mb > 0 && vm.memory_max_mb > 0 && vm.memory_min_mb <= vm.memory_max_mb
    ])
    error_message = "Each VM must have memory_min_mb <= memory_max_mb and both must be > 0."
  }
}

locals {
  resolved_vms = {
    for name, vm in var.vms : name => {
      vm_id           = vm.vm_id
      vm_sops_key     = name
      cpu_cores       = coalesce(try(vm.cpu_cores, null), 4)
      memory_max_mb   = coalesce(try(vm.memory_max_mb, null), 2048)
      memory_min_mb   = coalesce(try(vm.memory_min_mb, null), coalesce(try(vm.memory_max_mb, null), 2048))
      disk_size_gb    = coalesce(try(vm.disk_size_gb, null), 20)
      ci_user         = try(local.sops_config.vms[name].user, null)
      ci_password     = try(local.sops_config.vms[name].password, null)
      ssh_key_paths   = distinct(compact(vm.ssh_public_key_paths))
      network_bridge  = coalesce(try(vm.network_bridge, null), var.default_network_bridge)
      ipv4_address    = coalesce(try(vm.ipv4_address, null), "dhcp")
      ipv4_gateway    = try(vm.ipv4_gateway, null)
      start_on_create = coalesce(try(vm.start_on_create, null), true)
    }
  }
}

resource "proxmox_virtual_environment_vm" "vms" {
  for_each = local.resolved_vms

  name      = each.key
  node_name = var.proxmox_node_name
  vm_id     = each.value.vm_id
  started   = each.value.start_on_create

  lifecycle {
    ignore_changes = [
      started,
    ]

    precondition {
      condition = (
        each.value.ci_user != null &&
        trimspace(nonsensitive(each.value.ci_user)) != "" &&
        each.value.ci_password != null &&
        trimspace(nonsensitive(each.value.ci_password)) != ""
      )
      error_message = format("Missing or invalid VM credentials in proxmox_sops_file at vms.%s (expected object with non-empty 'user' and 'password').", each.value.vm_sops_key)
    }
  }

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu {
    cores = each.value.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_max_mb
    floating  = each.value.memory_min_mb
  }

  disk {
    datastore_id = var.storage_pool
    interface    = var.root_disk_interface
    size         = each.value.disk_size_gb
  }

  network_device {
    bridge = each.value.network_bridge
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  initialization {
    datastore_id = var.cloudinit_storage_pool

    user_account {
      username = each.value.ci_user
      password = each.value.ci_password
      keys = [
        for path in each.value.ssh_key_paths :
        trimspace(file(pathexpand(path)))
      ]
    }

    ip_config {
      ipv4 {
        address = each.value.ipv4_address
        gateway = each.value.ipv4_gateway
      }
    }
  }
}

output "vm_ids" {
  description = "VM IDs created by this stack"
  value       = { for name, vm in proxmox_virtual_environment_vm.vms : name => vm.vm_id }
}
