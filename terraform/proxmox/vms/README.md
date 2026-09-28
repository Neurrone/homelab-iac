# Proxmox VMs (Terraform)

This stack clones one or more VMs from a Packer-built Proxmox template.

## Why `full = true`

`full = true` creates a full clone with its own independent disk data.
Changes in one VM won't affect others and clones do not depend on the template's storage chain.

## Quick start

1. Copy vars template:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
2. Fill in values in `terraform.tfvars`.
3. Create SOPS files from templates:
   ```bash
   cp secrets.sops.json.example secrets.sops.json
   cp ../../tofu.env.sops.json.example ../../tofu.env.sops.json
   ```
4. Encrypt SOPS files after adding real values:
   ```bash
   sops -e -i secrets.sops.json
   sops -e -i ../../tofu.env.sops.json
   ```
5. Run OpenTofu through SOPS env injection:
   ```bash
   just init
   just plan
   just apply
   ```

## VM settings

Per-VM entries in `vms` support:
- `ssh_public_key_paths`: required list of one or more public key file paths.
- `memory_min_mb` and `memory_max_mb`: memory ballooning range (min <= max).
- `ipv4_address`: `dhcp` or static CIDR (for example `192.168.2.170/24`).
- `ipv4_gateway`: optional IPv4 gateway for static addressing (for example `192.168.2.1`).
- `start_on_create`: optional initial power state on create (runtime power state drift is ignored).

Networking model:
- Static VM IPs come from this Terraform stack via Proxmox cloud-init metadata (`ipv4_address` / `ipv4_gateway`).
- DNS defaults are baked into the Packer template (`1.1.1.1`, `8.8.8.8`) during image build.
- To apply DNS template changes to an existing VM, rebuild the template and recreate the VM from that template.

Cloud-init credentials are required from `secrets.sops.json` under top-level `vms`:
- VM key must match the VM name exactly.
  Example: VM `workstation-01` uses SOPS key `vms.workstation-01`.
- `vms.<vm_name>` must contain an object with non-empty `user` and `password`:
  - `vms.workstation-01.user`
  - `vms.workstation-01.password`

Top-level disk setting:
- `root_disk_interface`: slot used for the primary/root disk (default `virtio0`).
  Set this to match your template so Terraform manages one main disk instead of adding another.

## SOPS + OpenTofu credentials and state encryption

This module requires encrypted credentials via the `carlpett/sops` provider.
Proxmox endpoint and auth are read only from the SOPS file (no plaintext variable fallbacks).

1. Create `secrets.sops.json` from template:
   ```bash
   cp secrets.sops.json.example secrets.sops.json
   ```
2. Edit `secrets.sops.json` with real credentials (username/password or API token), then encrypt:
   ```bash
   sops -e -i secrets.sops.json
   ```
3. Set in `terraform.tfvars`:
   ```hcl
   proxmox_sops_file = "secrets.sops.json"
   ```
4. Create shared `terraform/tofu.env.sops.json` from template:
   ```bash
   cp ../../tofu.env.sops.json.example ../../tofu.env.sops.json
   ```
5. Set `TF_VAR_state_encryption_passphrase` in `terraform/tofu.env.sops.json`, then encrypt:
   ```bash
   sops -e -i ../../tofu.env.sops.json
   ```
6. Initialize providers:
   ```bash
   sops exec-env ../../tofu.env.sops.json 'tofu init'
   ```
7. Plan/apply as usual:
   ```bash
   sops exec-env ../../tofu.env.sops.json 'tofu plan'
   sops exec-env ../../tofu.env.sops.json 'tofu apply'
   ```

Supported keys in the SOPS file:

- `proxmox_endpoint`
- `proxmox_username` + `proxmox_password`
- or `proxmox_api_token`
- `vms`: map of VM credentials keyed by exact VM name, each with `user` and `password`

Provide exactly one auth method: either `proxmox_api_token` or `proxmox_username` + `proxmox_password`.

State encryption env keys (in shared `terraform/tofu.env.sops.json`):
- `TF_VAR_state_encryption_passphrase`: passphrase used by OpenTofu PBKDF2 key provider.

## Local state

Terraform uses local state by default in this directory (`terraform.tfstate`).
That is a common starting point for homelabs, but still treat state as sensitive.
This stack now configures OpenTofu state encryption (`pbkdf2` + `aes_gcm`) and includes an unencrypted fallback for one-time migration from existing plaintext state.
