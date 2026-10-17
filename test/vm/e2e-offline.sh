#!/bin/bash
# The directory's answers over time: an expired password must be changed first; cached sign-in works with the DC
# down (but not for people never seen here), and everything recovers when it returns. Needs DC + VM.
source "$(dirname "$0")/lib.sh"
NEW='D4ve-New-Pw!'
trap 'docker start oi-test-dc >/dev/null 2>&1; dc user delete dave >/dev/null' EXIT
fresh
dc user delete dave >/dev/null; dc user create dave "$PW" --must-change-at-next-login >/dev/null; dc group addmembers oi-laptop-users dave >/dev/null
enroll_ok --groups oi-laptop-users

echo "[expired password]"
for svc in sddm sshd; do
  out=$(pt "$svc" dave "$PW"); [[ $out == DENIED*"new one required"* ]] && ok "$svc: refused, new password required" || bad "$svc: $out"
done
reset_locks
[[ $("${V[@]}" "sudo -u dave python3 -I /tmp/pamtest.py$(q passwd dave "$PW" --chauthtok "$NEW")" 2>&1) == PASSWORD-CHANGED* ]] && ok "dave changes it with passwd" || bad "dave passwd"
expect ALLOWED "dave signs in with the new password" --session sddm dave "$NEW"

echo "[domain controller down]"
expect ALLOWED "alice signs in once while online (fills the cache)" system-auth alice "$PW"
docker stop oi-test-dc >/dev/null; sleep 3
expect ALLOWED "alice (cached) signs in offline" system-auth alice "$PW"
expect DENIED  "alice, wrong password, refused offline" system-auth alice wrong
expect DENIED  "bob (never signed in here) refused offline" system-auth bob "$PW"
expect ALLOWED "tester (local) fine offline" system-auth tester tester

echo "[domain controller back]"
docker start oi-test-dc >/dev/null
timeout 120 bash -c 'until docker exec oi-test-dc samba-tool domain level show >/dev/null 2>&1; do sleep 2; done'
"${V[@]}" 'sudo systemctl kill -s SIGUSR2 sssd' 2>/dev/null   # ask sssd to go online now instead of at its next retry
for _ in $(seq 20); do out=$(pt system-auth bob "$PW"); [[ $out == ALLOWED* ]] && break; sleep 3; done
[[ $out == ALLOWED* ]] && ok "bob signs in once the DC is back" || bad "after recovery: $out"
leave
result
