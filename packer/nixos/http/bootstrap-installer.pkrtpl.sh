#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/usr/bin:/bin:$${PATH}"

echo "Bootstrapping live NixOS installer for nixos-anywhere..."

# Set a temporary password for the default installer user expected by nixos-anywhere no-OS flow.
echo "nixos:${ssh_password}" | chpasswd

# Ensure SSH is up for Packer (communicator) and nixos-anywhere (shell-local).
systemctl start sshd
systemctl is-active --quiet sshd

ip -brief addr || true

echo "Installer bootstrap complete; waiting for SSH connections."
