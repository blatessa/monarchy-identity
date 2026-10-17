#!/bin/bash
# Boot the Arch client VM (KVM, UEFI, user-mode net). SSH: localhost:2222. Ctrl-a x quits.
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
IMG="$H/images/client.qcow2"
mkdir -p "$H/images" "$H/keys"
# test-VM SSH key: generated on first use (never committed); its public half is rendered into the cloud-init seed
[[ -f $H/keys/id_oi ]] || ssh-keygen -q -t ed25519 -N '' -C oi-test -f "$H/keys/id_oi"
PUB="$(ssh-keygen -y -f "$H/keys/id_oi") oi-test"
SEED="$H/images/seed"; mkdir -p "$SEED"; cp "$H/seed/meta-data" "$SEED/"
sed "s|@SSH_PUBKEY@|$PUB|" "$H/seed/user-data.tmpl" > "$SEED/user-data"
[[ -f $IMG ]] || { qemu-img create -f qcow2 -F qcow2 -b "$H/images/Arch-Linux-x86_64-cloudimg.qcow2" "$IMG" 30G; }
VARS="$H/images/OVMF_VARS.fd"; [[ -f $VARS ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$VARS"
# cloud-init seed server. A stale one (e.g. started from a since-renamed directory) serves nothing useful and
# the VM silently provisions with defaults, so replace any existing listener on :8000 and serve an absolute path.
OLD=$(ss -ltnp 2>/dev/null | sed -n '/:8000 /s/.*pid=\([0-9]*\).*/\1/p' | head -1); [[ -z $OLD ]] || kill "$OLD" 2>/dev/null || true
sleep 0.3
python3 -m http.server 8000 --bind 127.0.0.1 --directory "$SEED" >/dev/null 2>&1 & HTTP=$!
trap 'kill $HTTP 2>/dev/null' EXIT
MON="$H/images/monitor.sock"; rm -f "$MON"
# -vga std + a monitor socket let tests type keys (sendkey) and take screenshots (screendump) of the greeter
exec qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4096 -nographic -vga std -monitor unix:"$MON",server,nowait \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$IMG",if=virtio \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 -device virtio-net-pci,netdev=n0 \
  -smbios "type=1,serial=ds=nocloud;s=http://10.0.2.2:8000/"
