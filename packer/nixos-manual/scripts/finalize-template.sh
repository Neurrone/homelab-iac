#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

# shellcheck disable=SC1091
source /etc/nixos/packer/lib/serial-mirror.sh
setup_serial_mirror

test -d /etc/nixos/packer
ln -sfn ./packer/final/configuration.nix /etc/nixos/configuration.nix

echo "Switching installed system to final template configuration..."
nixos-rebuild switch
/run/current-system/sw/bin/sshd -t

# Remove bootstrap-only config fragments so the template does not retain the temp hash.
rm -rf /etc/nixos/packer/bootstrap

# Remove the temporary bootstrap user before converting to a template.
userdel -f -r nixos || true

cloud-init clean --logs || true
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
nix-collect-garbage -d || true
journalctl --rotate || true
journalctl --vacuum-time=1s || true
rm -rf /tmp/* /var/tmp/*

echo "Template finalized. Powering off..."
systemctl poweroff
