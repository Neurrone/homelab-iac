#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin:$${PATH}"

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

echo "Bootstrapping live NixOS installer for manual Packer install..."

# Set a temporary password for the default installer user so Packer can SSH in.
printf '%s\n' 'nixos:${ssh_password}' | run_as_root chpasswd

# Ensure the SSH user can run the installer script as root without an interactive prompt.
run_as_root install -d -m 0755 /etc/sudoers.d
run_as_root sh -c "printf 'nixos ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/90-packer-nixos"
run_as_root chmod 0440 /etc/sudoers.d/90-packer-nixos

# Ensure SSH is up for the Packer communicator.
run_as_root systemctl start sshd
run_as_root systemctl is-active --quiet sshd
run_as_root systemctl start serial-getty@ttyS0.service || true
run_as_root sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin) ' || true

ip -brief addr || true

echo "Installer bootstrap complete; waiting for SSH connections."
