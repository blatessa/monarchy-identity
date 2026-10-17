#!/bin/bash
# Check the lab prerequisites and state; prints the exact next command for anything missing. Exit 0 = ready for e2e.
cd "$(dirname "$0")/.." || exit 1
rc=0
ok() { printf '  ok    %s\n' "$1"; }
no() { printf '  MISSING %s\n        -> %s\n' "$1" "$2"; rc=1; }
for c in docker qemu-system-x86_64 qemu-img ssh ssh-keygen python3 curl node; do
  command -v "$c" >/dev/null && ok "$c" || no "$c" "install it (Arch: docker qemu-full openssh python curl nodejs)"
done
[[ -w /dev/kvm ]] && ok "/dev/kvm usable" || no "/dev/kvm" "enable virtualization and add yourself to the kvm group"
[[ -f /usr/share/edk2/x64/OVMF_CODE.4m.fd ]] && ok "OVMF firmware" || no "OVMF firmware" "install edk2-ovmf"
[[ -f test/vm/images/Arch-Linux-x86_64-cloudimg.qcow2 ]] && ok "Arch cloud image" || no "Arch cloud image" "test/vm/fetch-image.sh"
[[ -f test/vm/keys/id_oi ]] && ok "VM ssh key" || no "VM ssh key" "created automatically by test/vm/run.sh on first boot"
docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oi-test-dc && ok "directory container running" \
  || no "directory container (oi-test-dc)" "(cd test/dc && docker compose up -d && ./seed-users.sh)"
if [[ -f test/vm/keys/id_oi ]] && ssh -i test/vm/keys/id_oi -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=4 \
     -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 2222 tester@127.0.0.1 true 2>/dev/null; then
  ok "VM reachable on 127.0.0.1:2222"
else no "VM not reachable" "(cd test/vm && (setsid ./run.sh </dev/null >vm.log 2>&1 &)); first boot takes ~1 min, then test/vm/deploy.sh --fixtures"; fi
[[ $rc == 0 ]] && echo "lab ready" || echo "lab NOT ready"
exit $rc
