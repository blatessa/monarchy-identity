#!/bin/bash
# Check the lab prerequisites and state; prints the exact next command for anything missing. Exit 0 = ready for e2e.
cd "$(dirname "$0")/.." || exit 1
rc=0
ok() { printf '  ok    %s\n' "$1"; }
no() { printf '  MISSING %s\n        -> %s\n' "$1" "$2"; rc=1; }
for c in docker qemu-system-x86_64 qemu-img ssh ssh-keygen python3 curl node; do
  command -v "$c" >/dev/null && ok "$c" || no "$c" "install it (Arch: docker qemu-full openssh python curl nodejs)"
done
{ command -v mkdocs || [[ -x .venv/bin/mkdocs ]]; } >/dev/null && ok "mkdocs (for docs changes: mkdocs build --strict)" \
  || printf '  note  mkdocs missing: only needed when you change docs/\n        -> python -m venv .venv && .venv/bin/pip install -r .github/docs-requirements.txt\n'
[[ -w /dev/kvm ]] && ok "/dev/kvm usable" || no "/dev/kvm" "enable virtualization and add yourself to the kvm group"
[[ -f /usr/share/edk2/x64/OVMF_CODE.4m.fd ]] && ok "OVMF firmware" || no "OVMF firmware" "install edk2-ovmf"
[[ -f test/vm/images/Arch-Linux-x86_64-cloudimg.qcow2 ]] && ok "Arch cloud image" || no "Arch cloud image" "test/vm/fetch-image.sh"
[[ -f test/vm/keys/id_oi ]] && ok "VM ssh key" || no "VM ssh key" "created automatically by test/vm/run.sh on first boot"
docker ps --format '{{.Names}}' 2>/dev/null | grep -qx oi-test-dc && ok "directory container running" \
  || no "directory container (oi-test-dc)" "(cd test/dc && docker compose up -d && ./seed-users.sh)"
if [[ -f test/vm/keys/id_oi ]] && ssh -i test/vm/keys/id_oi -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=4 \
     -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 2222 tester@127.0.0.1 true 2>/dev/null; then
  ok "VM reachable on 127.0.0.1:2222"
  ssh -i test/vm/keys/id_oi -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR -p 2222 tester@127.0.0.1 'systemctl is-active -q polkit-agent-helper.socket' 2>/dev/null && ok "VM has polkit" \
    || no "VM has no polkit (VMs made before it was in the seed)" "ssh -i test/vm/keys/id_oi -p 2222 tester@127.0.0.1 'sudo pacman -S --noconfirm --needed polkit && sudo systemctl start polkit-agent-helper.socket'"
else no "VM not reachable" "(cd test/vm && (setsid ./run.sh </dev/null >vm.log 2>&1 &)); first boot takes ~1 min, then test/vm/deploy.sh --fixtures"; fi
# Entra (opt-in: test/vm/e2e-entra.sh skips without a tenant, so these are notes, not MISSING)
note() { printf '  note  %s\n        -> %s\n' "$1" "$2"; }
entra_vars=(ENTRA_TENANT ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET ENTRA_ALICE ENTRA_ALICE_PASSWORD ENTRA_BOB ENTRA_BOB_PASSWORD ENTRA_CAROL ENTRA_CAROL_PASSWORD)
entra_mfa_vars=(ENTRA_DAVE ENTRA_DAVE_PASSWORD ENTRA_DAVE_TOTP_SECRET)
if [[ -z ${ENTRA_LAB_ENV:-} || ! -r ${ENTRA_LAB_ENV:-} ]]; then
  note "no Entra test tenant: e2e-entra.sh will SKIP" "export ENTRA_LAB_ENV=/path/to/lab.env (outside the repo; contents in docs/dev/testing.md#labs-for-other-directories)"
else
  unset_vars=$(set -a; source "$ENTRA_LAB_ENV" >/dev/null 2>&1; for v in "${entra_vars[@]}"; do [[ -n ${!v:-} ]] || printf '%s ' "$v"; done)
  [[ -z $unset_vars ]] && ok "Entra test tenant ($ENTRA_LAB_ENV)" || note "$ENTRA_LAB_ENV lacks: $unset_vars" "add them (docs/dev/testing.md#labs-for-other-directories)"
  unset_vars=$(set -a; source "$ENTRA_LAB_ENV" >/dev/null 2>&1; for v in "${entra_mfa_vars[@]}"; do [[ -n ${!v:-} ]] || printf '%s ' "$v"; done)
  [[ -z $unset_vars ]] && ok "Entra MFA test user" || note "no Entra MFA test user ($unset_vars): the second-step checks will SKIP" "docs/dev/testing.md#labs-for-other-directories"
  ssh -i test/vm/keys/id_oi -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 2222 tester@127.0.0.1 'pacman -Q himmelblau' >/dev/null 2>&1 \
    && ok "VM has himmelblau" || note "VM has no himmelblau" "the suites install it from test/vm/images/himmelblau-*.pkg.tar.zst (build pkgbuilds/himmelblau from omacom/omarchy-pkgs)"
  az account show >/dev/null 2>&1 && ok "az signed in (e2e-entra.sh deletes the devices it registers)" \
    || note "az not signed in: delete the device 'oi-client' in the Entra admin center after each run" "az login --tenant <tenant> --allow-no-subscriptions"
fi
[[ $rc == 0 ]] && echo "lab ready" || echo "lab NOT ready"
exit $rc
