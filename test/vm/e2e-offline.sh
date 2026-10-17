#!/bin/bash
# Offline (DC unreachable) behaviour: cached credentials work, uncached users and wrong passwords don't.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
pt() { "${V[@]}" "sudo python3 -I ~/pamtest.py system-auth $1 '$2'" 2>&1; }
expect() { local out; out=$(pt "$2" "$3"); [[ $out == $1* ]] && ok "$4" || bad "$4 (got: $out)"; }
scp -q -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P 2222 pamtest.py tester@127.0.0.1:/home/tester/
./deploy.sh --fixtures >/dev/null
trap 'docker start oi-test-dc >/dev/null 2>&1' EXIT
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users" 2>&1)
[[ $out == *"enrolled in"* ]] && ok enroll || { bad enroll; echo "$out" | sed 's/^/      /'; }
"${V[@]}" 'for u in alice bob; do sudo faillock --user $u --reset; done' 2>/dev/null
echo "[online: alice signs in once (populates the cache); bob never does]"
expect ALLOWED alice "$PW" "alice online"
echo "[DC goes away]"
docker stop oi-test-dc >/dev/null; sleep 3
S=$(date +%s); expect ALLOWED alice "$PW" "alice (cached) allowed offline"; echo "  (took $(( $(date +%s)-S ))s)"
expect DENIED alice wrong "alice wrong password denied offline"
expect DENIED bob "$PW" "bob (never signed in here) denied offline"
expect ALLOWED tester tester "local break-glass works offline"
"${V[@]}" '~/oi/bin/monarchy-identity status --json' | grep -q '"enrolled":true' && ok "status still reports enrolled offline" || bad "status offline"
echo "[DC returns]"
docker start oi-test-dc >/dev/null
timeout 120 bash -c 'until docker exec oi-test-dc samba-tool domain level show >/dev/null 2>&1; do sleep 3; done'
"${V[@]}" 'sudo sssctl domain-status corp.test >/dev/null 2>&1; sudo systemctl kill -s SIGUSR2 sssd 2>/dev/null; true'
for _ in $(seq 20); do out=$(pt bob "$PW"); [[ $out == ALLOWED* ]] && break; sleep 5; done
[[ $out == ALLOWED* ]] && ok "bob allowed again once the DC is back (backend recovered)" || bad "bob after recovery: $out"
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
