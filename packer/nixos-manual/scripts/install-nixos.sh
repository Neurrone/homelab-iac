#!/usr/bin/env bash
set -euo pipefail

: "${BOOTSTRAP_PASSWORD:?BOOTSTRAP_PASSWORD is required}"
: "${NIXOS_STATE_VERSION:?NIXOS_STATE_VERSION is required}"

export PATH="/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

# shellcheck disable=SC1091
source /tmp/nix/lib/serial-mirror.sh
setup_serial_mirror

disk="/dev/vda"
root_part="${disk}2"
packer_nix_src="/tmp/nix"
target_nix_dir="/mnt/etc/nixos/packer"

echo "Partitioning ${disk} for a manual NixOS install..."

swapoff -a || true
umount -R /mnt 2>/dev/null || true

wipefs -af "${disk}" || true
sgdisk --zap-all "${disk}"
sgdisk -o "${disk}"
sgdisk -n 1:1MiB:+1MiB -t 1:EF02 -c 1:bios_grub "${disk}"
sgdisk -n 2:0:0 -t 2:8300 -c 2:nixos_root "${disk}"
partprobe "${disk}" || true
udevadm settle

mkfs.ext4 -F -L nixos "${root_part}"
mount /dev/disk/by-label/nixos /mnt

if [[ ! -d "${packer_nix_src}" ]]; then
  echo "Missing uploaded NixOS config directory at ${packer_nix_src}" >&2
  exit 1
fi

echo "Installing static NixOS config files..."
install -d -m 0755 "${target_nix_dir}"
cp -R "${packer_nix_src}/." "${target_nix_dir}/"

pw_hash="$(printf '%s' "${BOOTSTRAP_PASSWORD}" | openssl passwd -6 -stdin)"

cat >"${target_nix_dir}/state-version.nix" <<EOF
{ ... }: {
  system.stateVersion = "${NIXOS_STATE_VERSION}";
}
EOF

cat >"${target_nix_dir}/bootstrap/bootstrap-secrets.nix" <<EOF
{ ... }: {
  users.users.nixos.hashedPassword = "${pw_hash}";
}
EOF

ln -sfn ./packer/bootstrap/configuration.nix /mnt/etc/nixos/configuration.nix

echo "Installing NixOS..."
nixos-install --root /mnt --no-root-passwd

sync
echo "Install complete. Rebooting into the installed system..."
reboot
