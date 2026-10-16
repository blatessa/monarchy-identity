#!/bin/bash
# Lockout safety: local-fallback precondition and the auto-revert dead-man's switch. Needs DC + VM.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
ENR="sudo ~/oi/bin/monarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users"
enrol() { echo "$PW" | "${V[@]}" "$ENR $*" 2>&1; }
leave() { echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1; }
st() { "${V[@]}" '~/oi/bin/monarchy-identity status --json'; }
pam_stock() { for f in system-auth omarchy-lock-password; do "${V[@]}" "cat /etc/pam.d/$f" | diff -q - fixtures/pam.d/$f >/dev/null || return 1; done; }
./deploy.sh --fixtures >/dev/null; leave
trap '"${V[@]}" "sudo passwd -u tester >/dev/null 2>&1; sudo systemctl stop monarchy-identity-revert.timer 2>/dev/null"' EXIT

echo "[local fallback precondition]"
"${V[@]}" 'sudo passwd -l tester' >/dev/null 2>&1
out=$(enrol)
[[ $out == *"no local account with a usable password"* ]] && ok "refused: only local user has a locked password" || bad "not refused: $out"
pam_stock && ok "nothing was modified (PAM still stock)" || bad "PAM modified despite refusal"
[[ $(st) == *'"enrolled":false'* ]] && ok "not enrolled" || bad "state changed"
out=$(enrol --allow-no-local-fallback); [[ $out == *"enrolled in"* ]] && ok "--allow-no-local-fallback overrides" || bad "override failed: $out"
leave; "${V[@]}" 'sudo passwd -u tester' >/dev/null 2>&1
out=$(enrol); [[ $out == *"local fallback accounts: tester"* && $out == *"enrolled in"* ]] && ok "allowed with a usable local account (tester)" || bad "fallback not detected: $out"
leave

echo "[auto-revert: unconfirmed]"
out=$(enrol --confirm-within 1); [[ $out == *"AUTO-REVERT in 1 min"* ]] && ok "enrol schedules auto-revert" || bad "no schedule: $out"
[[ $(st) == *'"revert_pending":true'* && $(st) == *'"enrolled":true'* ]] && ok "status: enrolled, revert_pending" || bad "status: $(st)"
echo "  ...waiting for the timer (up to 150s)"
for _ in $(seq 30); do sleep 5; [[ $(st) == *'"enrolled":false'* ]] && break; done
[[ $(st) == *'"enrolled":false'* && $(st) == *'"revert_pending":false'* ]] && ok "auto-reverted to local" || bad "not reverted: $(st)"
pam_stock && ok "PAM back to stock after auto-revert" || bad "PAM not stock after auto-revert"

echo "[auto-revert: confirmed]"
out=$(enrol --confirm-within 1); [[ $out == *"enrolled in"* ]] || bad "enrol: $out"
out=$("${V[@]}" 'sudo ~/oi/bin/monarchy-identity confirm' 2>&1); [[ $out == *"auto-revert cancelled"* ]] && ok "confirm cancels the timer" || bad "confirm: $out"
echo "  ...waiting 80s to prove it stays enrolled"; sleep 80
[[ $(st) == *'"enrolled":true'* && $(st) == *'"revert_pending":false'* ]] && ok "still enrolled after timer window" || bad "state: $(st)"
leave
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
