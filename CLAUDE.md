# CLAUDE.md

## Repository Overview

This is a homelab Infrastructure-as-Code (IaC) repository for managing my homelab.

- `ansible`: playbooks for deploying various Docker containers to multiple nodes, and performing routine maintenance tasks on the nodes
- `packer`: packer templates for Proxmox VMs
- `terraform`: VMs provisioned on Proxmox

## Secrets Management

The repository uses SOPS with age encryption for secrets management.

Always use sops to ensure that sensitive secrets like credentials are stored securely, never read them from plaintext files.

Never run commands that would decrypt or print secrets, since that exposes them.
