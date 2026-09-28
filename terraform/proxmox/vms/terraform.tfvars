proxmox_insecure  = true
proxmox_node_name = "proxmox"
proxmox_sops_file = "secrets.sops.json"

template_vm_id         = 101
storage_pool           = "Optane"
cloudinit_storage_pool = "Optane"
root_disk_interface    = "virtio0"
default_network_bridge = "vmbr0"

vms = {
  workstation-01 = {
    vm_id = 210
    ssh_public_key_paths = [
      ".ssh/ansible.pub",
      ".ssh/id_ed25519_non_resident_sk.pub",
      ".ssh/id_ed25519_non_resident_sk2.pub"
    ]
    cpu_cores       = 8
    memory_min_mb   = 4096
    memory_max_mb   = 16384
    disk_size_gb    = 100
    ipv4_address    = "192.168.2.170/24"
    ipv4_gateway    = "192.168.2.1"
    start_on_create = true
  }

  # Add another VM by adding another entry, for example:
  # workstation-02 = {
  #   vm_id = 9002
  # }
}
