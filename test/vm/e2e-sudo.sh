#!/bin/bash
# --sudo-groups: directory group -> sudo via a visudo-validated drop-in. Needs DC + VM.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
A="--realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users"
can() { "${V[@]}" "sudo sudo -l -U $1 2>&1" | grep -q "(ALL : ALL) ALL"; }
leave() { echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1; }

./deploy.sh --fixtures >/dev/null
leave

echo "[invalid input is refused before anything changes]"
for badval in "bad group" "a;b" 'x$(id)'; do
  out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $A --sudo-groups '$badval'" 2>&1)
  [[ $out == *"invalid --sudo-groups"* ]] && ok "refused: $badval" || bad "not refused: $badval -> $out"
done
"${V[@]}" 'test ! -e /etc/sudoers.d/50-monarchy-identity' && ok "no sudoers file written" || bad "sudoers file exists"

echo "[enrol with --sudo-groups oi-admins]"
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $A --sudo-groups oi-admins" 2>&1)
[[ $out == *"enrolled in"* ]] && ok enrol || { bad enrol; echo "$out" | sed 's/^/      /'; }
[[ $("${V[@]}" 'sudo stat -c "%a %U" /etc/sudoers.d/50-monarchy-identity') == "440 root" ]] && ok "drop-in is 0440 root" || bad "drop-in mode/owner"
can alice && ok "alice (in oi-admins) has sudo" || bad "alice lacks sudo"
can bob && bad "bob (not in oi-admins) has sudo" || ok "bob (may log in, not in oi-admins) has no sudo"
can carol && bad "carol has sudo" || ok "carol has no sudo"
"${V[@]}" 'sudo visudo -c' >/dev/null 2>&1 && ok "visudo -c clean for the whole config" || bad "visudo -c failed"

echo "[reassert restores a deleted drop-in]"
"${V[@]}" 'sudo rm -f /etc/sudoers.d/50-monarchy-identity; sudo ~/oi/bin/monarchy-identity reassert' >/dev/null 2>&1
can alice && ok "alice has sudo again after reassert" || bad "reassert did not restore sudo"

leave
"${V[@]}" 'test ! -e /etc/sudoers.d/50-monarchy-identity' && ok "leave removed the drop-in" || bad "drop-in left behind"
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
