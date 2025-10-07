# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a homelab Infrastructure-as-Code (IaC) repository for managing Docker-based services across multiple hosts (Proxmox and Linode VMs) using Ansible. The repository uses SOPS with age encryption for secrets management.

## Architecture

### Inventory Structure

- **Host Groups**: `proxmox_docker`, `linode_docker`, both children of `docker_vms` group
- **Inventory**: `ansible/inventory/hosts.yml`
- **Host Variables**: `ansible/host_vars/*.sops.yml` (SOPS-encrypted)
- **Group Variables**:
  - `ansible/group_vars/docker_vms.yml` - Common settings (timezone)
  - `ansible/group_vars/docker_vms.sops.yml` - Shared application secrets (SOPS-encrypted)

### Docker App Deployment Pattern

The repository uses a reusable `docker_app` role to deploy containerized applications:

1. **Role Location**: `ansible/roles/docker_app/`
2. **Template Storage**:
   - Docker Compose: `ansible/templates/{app_name}/docker-compose.yml.j2`
   - App Configs: `ansible/templates/{app_name}/{inventory_hostname}/config.yaml.j2` (for host-specific configs with secrets)
3. **Static Config Files**: `ansible/files/{inventory_hostname}/{app_name}/` (for host-specific non-templated configs)

### Playbook Patterns

- **App-Specific Playbooks**: `ansible/deploy-{app_name}.yml` - Deploy single application
- **Bulk Deployment**: `ansible/deploy-all-docker-apps.yml` - Deploy multiple apps using loop over `docker_apps` list
- **Utility**: `ansible/deploy-ssh-key.yml` - Interactive playbook for SSH key deployment

## Commands

### Ansible-related commands

Always `cd ansible` first if not already in the `ansible` subfolder, before running the commands in this section.

#### Running Playbooks

```bash
# Deploy specific application to all docker VMs
ansible-playbook deploy-gatus.yml

# Deploy all applications
ansible-playbook deploy-all-docker-apps.yml

# Deploy to specific host group
ansible-playbook deploy-gatus.yml --limit proxmox_docker

# Deploy specific app using tags (when using deploy-all-docker-apps.yml)
ansible-playbook deploy-all-docker-apps.yml --tags gatus

# Deploy SSH key (interactive)
ansible-playbook deploy-ssh-key.yml
```

#### SOPS Operations

SOPS is configured in `.sops.yaml` with age encryption. The `community.sops` vars plugin is enabled in `ansible.cfg` to auto-decrypt `.sops.yml` files in `group_vars/` and `host_vars/`.

```bash
# Edit encrypted host vars
sops host_vars/linode-docker-vm.sops.yml

# Edit shared application secrets
sops group_vars/docker_vms.sops.yml

# Encrypt new file
sops -e host_vars/new-host.yml > host_vars/new-host.sops.yml

# Decrypt to view
sops -d host_vars/linode-docker-vm.sops.yml
```
