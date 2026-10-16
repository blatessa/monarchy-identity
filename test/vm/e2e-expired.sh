#!/bin/bash
# Password flagged "must change at next logon": login is denied (new token required), the user can change
# it with passwd, then log in. Needs DC + VM. Creates and deletes its own user (dave).
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; NEW='D4ve-New-Pw!'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
dc() { docker exec oi-test-dc samba-tool "$@" >/dev/null 2>&1; }
pt() { local u=$2; if [[ $1 == passwd ]]; then "${V[@]}" "sudo -u $u python3 -I /tmp/pamtest.py $*" 2>&1; else "${V[@]}" "sudo python3 -I /tmp/pamtest.py $*" 2>&1; fi; }
expect() { local want=$1 desc=$2; shift 2; local out; out=$(pt "$@"); [[ $out == $want* ]] && ok "$desc" || bad "$desc (got: $out)"; }
trap 'dc user delete dave' EXIT
scp -q -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P 2222 pamtest.py tester@127.0.0.1:/home/tester/
./deploy.sh --fixtures >/dev/null; "${V[@]}" 'sudo install -m 644 ~/pamtest.py /tmp/pamtest.py'
dc user delete dave; dc user create dave "$PW" --must-change-at-next-login; dc group addmembers oi-laptop-users dave
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users" 2>&1)
[[ $out == *"enrolled in"* ]] && ok enrol || { bad enrol; echo "$out" | sed 's/^/      /'; }
"${V[@]}" 'sudo faillock --user dave --reset' 2>/dev/null

echo "[expired password]"
for svc in system-auth sddm login sshd; do
  expect DENIED "$svc: correct but expired password is not enough" $svc dave "$PW"
  out=$(pt $svc dave "$PW"); [[ $out == *"new one required"* ]] && ok "$svc: reason is 'new authentication token required'" || bad "$svc: wrong reason: $out"
done
"${V[@]}" 'sudo faillock --user dave --reset' 2>/dev/null
echo "[the user fixes it with passwd]"
expect PASSWORD-CHANGED "dave changes the expired password with passwd" passwd dave "$PW" --chauthtok "$NEW"
for svc in system-auth sddm sshd; do expect ALLOWED "$svc: dave can log in with the new password" --session $svc dave "$NEW"; done
expect DENIED "old password no longer works" system-auth dave "$PW"
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
