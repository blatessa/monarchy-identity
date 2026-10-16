#!/bin/bash
# Tests login.mode = assigned and any (groups is covered by e2e.sh). Needs DC + VM running.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
expect() { local out; out=$("${V[@]}" "sudo python3 -I ~/pamtest.py system-auth $3 '$4'" 2>&1); [[ $out == $2* ]] && ok "$1" || bad "$1 (got: $out)"; }
scp -q -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P 2222 pamtest.py tester@127.0.0.1:/home/tester/
./deploy.sh --fixtures >/dev/null
enrol() { echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/omarchy-identity leave --admin Administrator' >/dev/null 2>&1
  local out; out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/omarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator $*" 2>&1)
  [[ $out == *"enrolled in"* ]] && ok "enrol $*" || { bad "enrol $*"; echo "$out" | sed 's/^/      /'; }
  "${V[@]}" 'for u in alice bob carol tester; do sudo faillock --user $u --reset 2>/dev/null; done'; }
echo "[assigned: only alice]"; enrol --mode assigned --users alice
expect "alice (assigned) allowed" ALLOWED alice "$PW"
expect "bob (in group but NOT assigned) denied" DENIED bob "$PW"
expect "carol denied" DENIED carol "$PW"
expect "tester local still ok" ALLOWED tester tester
echo "[any: whole directory]"; enrol --mode any
expect "alice allowed" ALLOWED alice "$PW"
expect "carol (no group) allowed under any" ALLOWED carol "$PW"
expect "tester local still ok" ALLOWED tester tester
echo "[safety: groups mode requires --groups; bad mode rejected]"
out=$(echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/omarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --mode groups' 2>&1); [[ $out == *"needs --groups"* ]] && ok "groups without --groups refused (default deny)" || bad "groups w/o --groups: $out"
out=$(echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/omarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --mode bogus' 2>&1); [[ $out == *"bad --mode"* ]] && ok "bogus mode refused" || bad "bogus mode: $out"
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/omarchy-identity leave --admin Administrator' >/dev/null 2>&1
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
