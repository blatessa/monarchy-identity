#!/bin/bash
# Push the repo + Omarchy's real PAM files into the running VM. Run from anywhere.
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$H/../.." && pwd)"
SSHO=(-i "$H/keys/id_oi" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -P 2222)
vm() { ssh "${SSHO[@]/-P/-p}" -o LogLevel=ERROR tester@127.0.0.1 "$@"; }
tar -C "$R" --exclude=test --exclude=.git -czf - . | vm 'rm -rf ~/oi && mkdir ~/oi && tar -xzf - -C ~/oi'
# --fixtures = reset the VM to stock Omarchy PAM/SDDM files AND no installed monarchy-identity package (its pacman
# hook would repair drift before the suites can observe it).
if [[ ${1:-} == --fixtures ]]; then
  # lab reset: stale computer accounts in the directory (enrollment now refuses to take over an existing one)
  for c in 'OI-CLIENT$' 'LAPTOP-0042$' 'LAPTOP-0099$'; do docker exec oi-test-dc samba-tool computer delete "$c" >/dev/null 2>&1 || true; done
  vm 'sudo systemctl stop sddm 2>/dev/null; sudo pacman -R --noconfirm monarchy-identity >/dev/null 2>&1; sudo rm -f /etc/sddm.conf.d/zz-vm-x11.conf; true'
  # faillock counts failures by name for 15 minutes, across suites: suites that run back to back would lock their test
  # users (deny=10). By file, because `faillock --user` needs the user to exist and suites delete theirs.
  vm 'sudo rm -f /run/faillock/*'
fi
[[ ${1:-} == --fixtures ]] && tar -C "$H/fixtures" -czf - pam.d sddm.conf.d | vm 'sudo tar -xzf - -C /etc --no-same-owner && sudo chown -R root:root /etc/pam.d /etc/sddm.conf.d'
echo deployed
