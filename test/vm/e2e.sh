#!/bin/bash
# End-to-end test of the sssd provider against the Samba AD + VM. Needs DC and VM running.
# Usage: test/vm/e2e.sh        (deploys code, runs enrol -> policy matrix -> drift/reassert -> leave)
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
expect() { # expect <desc> <want ALLOWED|DENIED> <service> <user> <password>
  local out; out=$("${V[@]}" "sudo python3 -I ~/pamtest.py $3 $4 '$5'" 2>&1)
  [[ $out == $2* ]] && ok "$1" || bad "$1 (got: $out)"; }
scp -q -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P 2222 pamtest.py tester@127.0.0.1:/home/tester/
./deploy.sh --fixtures >/dev/null
"${V[@]}" 'sudo faillock --user alice --reset; sudo faillock --user bob --reset; sudo faillock --user carol --reset; sudo faillock --user tester --reset' 
echo "[enrol]"
# clean slate: leave if a previous run left us enrolled
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users" 2>&1)
[[ $out == *"enrolled in"* ]] && ok enrol || { bad "enrol"; echo "$out" | sed 's/^/      /'; }
# reset AFTER enrol: before it, directory users don't resolve and the reset is a silent no-op
"${V[@]}" 'for u in alice bob carol tester; do sudo faillock --user $u --reset; done' 2>/dev/null
echo "[policy: groups=oi-laptop-users]"
for svc in system-auth omarchy-lock-password; do
  expect "$svc alice (allowed group) right pw" ALLOWED $svc alice "$PW"
  expect "$svc bob   (allowed group) right pw" ALLOWED $svc bob "$PW"
  expect "$svc carol (NOT in group)   denied"  DENIED  $svc carol "$PW"
  expect "$svc tester (local break-glass)"     ALLOWED $svc tester tester
  expect "$svc bob wrong pw denied"            DENIED  $svc bob wrong
done
echo "[drift + reassert]"
"${V[@]}" 'sudo cp ~/oi/../../../etc/pam.d/system-auth /dev/null 2>/dev/null; sudo python3 -I ~/oi/lib/pamedit.py remove /etc/pam.d/system-auth'
"${V[@]}" '~/oi/bin/monarchy-identity status --json' | grep -q '"pam_system_auth":"false"' && ok "drift detected by status" || bad "drift detected"
"${V[@]}" 'sudo ~/oi/bin/monarchy-identity reassert' >/dev/null 2>&1
expect "alice allowed after reassert" ALLOWED system-auth alice "$PW"
echo "[leave]"
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
for f in system-auth omarchy-lock-password; do "${V[@]}" "cat /etc/pam.d/$f" | diff -q - fixtures/pam.d/$f >/dev/null && ok "$f restored to stock" || bad "$f restored"; done
[[ $(docker exec oi-test-dc samba-tool computer list | grep -c 'OI-CLIENT') -eq 0 ]] && ok "computer account removed" || bad "computer account removed"
expect "tester still ok after leave" ALLOWED system-auth tester tester
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
