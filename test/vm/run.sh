#!/bin/bash
# Boot the Arch client VM (KVM, UEFI, user-mode net). SSH: localhost:2222. Ctrl-a x quits.
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
IMG="$H/images/client.qcow2"
[[ -f $IMG ]] || { qemu-img create -f qcow2 -F qcow2 -b "$H/images/Arch-Linux-x86_64-cloudimg.qcow2" "$IMG" 30G; }
VARS="$H/images/OVMF_VARS.fd"; [[ -f $VARS ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$VARS"
(cd "$H/seed" && python3 -m http.server 8000 --bind 127.0.0.1 >/dev/null 2>&1) & HTTP=$!
trap 'kill $HTTP 2>/dev/null' EXIT
exec qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4096 -nographic \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$IMG",if=virtio \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 -device virtio-net-pci,netdev=n0 \
  -smbios "type=1,serial=ds=nocloud;s=http://10.0.2.2:8000/"
