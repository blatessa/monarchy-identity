#!/bin/bash
# Password changes through the real `passwd` PAM service: directory user (via pam_sss) and local user. Needs DC + VM.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; NEW='N3w-Passw0rd!'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
# Real `passwd` is setuid-root with the caller's real uid. pam_sss rejects root-initiated resets, so
# directory users must run as themselves; local users need root to write /etc/shadow (as setuid does).
pt() { local u=$2; if [[ $1 == passwd && $u != tester ]]; then "${V[@]}" "sudo -u $u python3 -I /tmp/pamtest.py $*" 2>&1; else "${V[@]}" "sudo python3 -I /tmp/pamtest.py $*" 2>&1; fi; }
expect() { local want=$1 desc=$2; shift 2; local out; out=$(pt "$@"); [[ $out == $want* ]] && ok "$desc" || bad "$desc (got: $out)"; }
scp -q -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P 2222 pamtest.py tester@127.0.0.1:/home/tester/
./deploy.sh --fixtures >/dev/null
"${V[@]}" 'sudo install -m 644 ~/pamtest.py /tmp/pamtest.py'
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
# always restore lab passwords, whatever happens
trap 'docker exec oi-test-dc samba-tool user setpassword alice --newpassword="$PW" >/dev/null 2>&1; "${V[@]}" "echo tester:tester | sudo chpasswd" >/dev/null 2>&1' EXIT
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users" 2>&1)
[[ $out == *"enrolled in"* ]] && ok enroll || { bad enroll; echo "$out" | sed 's/^/      /'; }
"${V[@]}" 'for u in alice tester; do sudo faillock --user $u --reset; done' 2>/dev/null
"${V[@]}" 'grep -c "^-password.*pam_sss" /etc/pam.d/system-auth' | grep -qx 1 && ok "password stack has pam_sss" || bad "password stack edit missing"

echo "[directory user changes password]"
expect PASSWORD-CHANGED "alice: passwd service changes the AD password" passwd alice "$PW" --chauthtok "$NEW"
expect ALLOWED "alice: NEW password works (system-auth)" system-auth alice "$NEW"
expect DENIED "alice: OLD password no longer works" system-auth alice "$PW"
"${V[@]}" 'sudo faillock --user alice --reset' 2>/dev/null
expect PASSWORD-CHANGED "alice: change back" passwd alice "$NEW" --chauthtok "$PW"
expect ALLOWED "alice: original password works again" system-auth alice "$PW"

echo "[local user unaffected]"
expect PASSWORD-CHANGED "tester: local passwd still changes the local password" passwd tester tester --chauthtok "tester2-pw"
expect ALLOWED "tester: new local password works" system-auth tester "tester2-pw"
expect PASSWORD-CHANGED "tester: change back" passwd tester "tester2-pw" --chauthtok "tester"
expect ALLOWED "tester: original works" system-auth tester tester
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
for f in system-auth; do "${V[@]}" "cat /etc/pam.d/$f" | diff -q - fixtures/pam.d/$f >/dev/null && ok "leave restores stock $f (incl. password stack)" || bad "$f not stock"; done
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
