#!/bin/bash
# Push the repo + Omarchy's real PAM files into the running VM. Run from anywhere.
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$H/../.." && pwd)"
SSHO=(-i "$H/keys/id_oi" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -P 2222)
vm() { ssh "${SSHO[@]/-P/-p}" -o LogLevel=ERROR tester@127.0.0.1 "$@"; }
tar -C "$R" --exclude=test --exclude=.git -czf - . | vm 'rm -rf ~/oi && mkdir ~/oi && tar -xzf - -C ~/oi'
[[ ${1:-} == --fixtures ]] && tar -C "$H/fixtures" -czf - pam.d | vm 'sudo tar -xzf - -C /etc --no-same-owner && sudo chown root:root /etc/pam.d/{system-auth,system-login,system-local-login,omarchy-lock-password}'
echo deployed
