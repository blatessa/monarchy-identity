#!/bin/bash
# Failure injection: a failed enrollment must leave the machine exactly as it was. Needs DC + VM.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
BASE="--realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups"
trap 'docker start oi-test-dc >/dev/null 2>&1' EXIT

./deploy.sh --fixtures >/dev/null
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1

# Snapshot of everything enrollment can touch; compare after each failure.
snap() { "${V[@]}" 'sudo bash -c "
  for f in /etc/pam.d/system-auth /etc/pam.d/omarchy-lock-password /etc/nsswitch.conf; do echo \"== \$f\"; cat \$f; done
  echo \"== sddm\"; ls /etc/sddm.conf.d; echo \"== sudoers.d\"; ls /etc/sudoers.d
  echo \"== sssd conf: \$(test -e /etc/sssd/sssd.conf && echo present || echo absent)\"
  echo \"== sssd active: \$(systemctl is-active sssd)\"
  echo \"== watcher: \$(systemctl is-active monarchy-identity-reassert.path)\"
  echo \"== provider: \$(grep ^provider /etc/monarchy-identity/config.toml 2>/dev/null | grep -q sssd && echo sssd || echo local-or-unset)\"
  echo \"== keytab: \$(test -e /etc/krb5.keytab && echo present || echo absent)\"
"' 2>&1; }
BEFORE=$(snap)

check_untouched() { # check_untouched <label>
  local after; after=$(snap)
  if [[ $after == "$BEFORE" ]]; then ok "$1: machine untouched afterwards"
  else bad "$1: state changed"; diff <(echo "$BEFORE") <(echo "$after") | head -12 | sed 's/^/      /'; fi
}
attempt() { # attempt <label> <expected error substring> <password> <extra args...>
  local label=$1 want=$2 pw=$3; shift 3
  local out rc q=""; for a in "$@"; do q+=" $(printf '%q' "$a")"; done   # %q: survive the remote shell intact
  out=$(echo "$pw" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $BASE$q" 2>&1); rc=$?
  [[ $rc -ne 0 ]] && ok "$label: exits non-zero" || bad "$label: exited 0"
  [[ -z $want || $out == *"$want"* ]] && ok "$label: reports the cause" || { bad "$label: message lacks '$want'"; echo "$out" | tail -3 | sed 's/^/      /'; }
  check_untouched "$label"
}

echo "[wrong admin password]"
attempt "wrong password" "" "not-the-password" --groups oi-laptop-users

echo "[group that does not exist in the directory (fails AFTER the domain join)]"
attempt "unresolvable group" "could not find the group" "$PW" --groups no-such-group-anywhere
[[ $(docker exec oi-test-dc samba-tool computer list | grep -c OI-CLIENT) -eq 0 ]] && ok "unresolvable group: computer account removed from the directory too" || bad "unresolvable group: computer account left in the directory"

echo "[domain controller unreachable]"
docker stop oi-test-dc >/dev/null; sleep 2
attempt "DC down" "" "$PW" --groups oi-laptop-users
docker start oi-test-dc >/dev/null
timeout 120 bash -c 'until docker exec oi-test-dc samba-tool domain level show >/dev/null 2>&1; do sleep 3; done'

echo "[bad arguments never get as far as touching anything]"
attempt "invalid realm (newline injection)" "invalid --realm" "$PW" --groups oi-laptop-users --realm $'corp.test\n[evil]'
attempt "missing groups" "needs --groups" "$PW"

echo "[recovery: a good enrollment still works after all that]"
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $BASE --groups oi-laptop-users" 2>&1)
[[ $out == *"enrolled in"* ]] && ok "clean enrollment succeeds after failures" || { bad "enrollment after failures"; echo "$out" | tail -4 | sed 's/^/      /'; }
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
