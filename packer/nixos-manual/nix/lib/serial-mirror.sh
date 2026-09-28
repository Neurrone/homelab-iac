#!/usr/bin/env bash

setup_serial_mirror() {
  local candidates=()
  local token
  local dev

  if [[ -r /proc/cmdline ]]; then
    for token in $(< /proc/cmdline); do
      if [[ "${token}" == console=* ]]; then
        dev="${token#console=}"
        dev="${dev%%,*}"
        if [[ "${dev}" != "tty0" ]]; then
          candidates+=("/dev/${dev}")
        fi
      fi
    done
  fi

  candidates+=(/dev/ttyS0 /dev/hvc0 /dev/ttyAMA0)

  for dev in "${candidates[@]}"; do
    [[ -c "${dev}" ]] || continue
    if exec 3>"${dev}"; then
      stty -F "${dev}" 115200 || true
      echo "[packer] serial mirror enabled on ${dev}" >&3 || true
      exec > >(tee -a /proc/self/fd/3) 2>&1
      return 0
    fi
  done

  echo "[packer] serial mirror unavailable (no writable serial tty found)" >&2
}
