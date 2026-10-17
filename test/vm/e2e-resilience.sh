#!/bin/bash
# What happens to LOCAL users when sssd is down or pam_sss.so is gone? They must be unaffected (a broken
# directory client must never lock out the local admin). Also: removing the package while enrolled unwinds PAM.
# Needs DC + VM. A restore timer inside the VM repairs pam_sss.so even if a check wrongly bricks logins.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=8 -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
pt() { "${V[@]}" "sudo python3 -I /tmp/pamtest.py $* 2>&1"; }
expect() { local want=$1 desc=$2; shift 2; local out; out=$(pt "$@"); [[ $out == $want* ]] && ok "$desc" || bad "$desc (got: ${out:-<nothing>})"; }
SSS=/usr/lib/security/pam_sss.so

scp -q -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P 2222 pamtest.py tester@127.0.0.1:/home/tester/
./deploy.sh --fixtures >/dev/null
"${V[@]}" 'sudo install -m 644 ~/pamtest.py /tmp/pamtest.py'
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users" 2>&1)
[[ $out == *"enrolled in"* ]] && ok enroll || { bad enroll; echo "$out" | sed 's/^/      /'; }
"${V[@]}" 'for u in alice tester; do sudo faillock --user $u --reset 2>/dev/null; done'

# safety net: if a check below bricks logins, this root timer (no PAM involved) puts the module back
restore_net() { "${V[@]}" "sudo systemd-run --quiet --unit=oi-restore-pam --on-active=${1}s /bin/sh -c 'test -e $SSS.off && mv $SSS.off $SSS'" >/dev/null 2>&1; }
cancel_net()  { "${V[@]}" 'sudo systemctl stop oi-restore-pam.timer oi-restore-pam.service' >/dev/null 2>&1; }

echo "[baseline]"
for s in sudo login sddm sshd; do expect ALLOWED "$s: local tester" $s tester tester; done
expect ALLOWED "alice (directory) can log in" sddm alice "$PW"

echo "[sssd stopped completely]"
"${V[@]}" 'sudo systemctl stop sssd; for u in $(systemctl list-units --all --no-legend "sssd*" | awk "{print \$1}"); do sudo systemctl stop $u 2>/dev/null; done; systemctl is-active sssd || true' >/dev/null 2>&1
for s in sudo login sddm sshd; do expect ALLOWED "$s: local tester still allowed with sssd down" $s tester tester; done
S0=$(date +%s); out=$(pt sddm alice "$PW"); T=$(( $(date +%s)-S0 ))
[[ $out == DENIED* || $out == *ALLOWED* ]] && ok "directory user gets a prompt answer with sssd down (${T}s): ${out%%:*}" || bad "directory user: $out"
"${V[@]}" 'sudo -n true' && ok "real sudo works" || bad "real sudo broken"
"${V[@]}" 'sudo systemctl start sssd'; sleep 5

echo "[pam_sss.so missing entirely (as if sssd were removed)]"
restore_net 120
"${V[@]}" "sudo mv $SSS $SSS.off"
for s in sudo login sddm sshd; do expect ALLOWED "$s: local tester still allowed with pam_sss.so GONE" $s tester tester; done
"${V[@]}" 'sudo -n true' && ok "real sudo works" || bad "real sudo broken"
out=$(pt sddm alice "$PW"); [[ $out == DENIED* ]] && ok "directory user is refused (fail closed), not waved through" || bad "directory user with module missing: ${out:-<nothing>}"
"${V[@]}" "sudo mv $SSS.off $SSS" ; cancel_net
"${V[@]}" 'sudo systemctl restart sssd'; sleep 6
"${V[@]}" 'sudo faillock --user alice --reset' 2>/dev/null
expect ALLOWED "alice works again once the module is back" sddm alice "$PW"

echo "[package removal while enrolled unwinds the PAM edits]"
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
./install-package.sh >/dev/null
out=$(echo "$PW" | "${V[@]}" "sudo /usr/bin/monarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users" 2>&1)
[[ $out == *"enrolled in"* ]] && ok "enroll with the installed package" || { bad "enroll (package)"; echo "$out" | sed 's/^/      /'; }
"${V[@]}" 'grep -q monarchy-identity /etc/pam.d/system-auth' && ok "PAM edited while enrolled" || bad "PAM not edited"
"${V[@]}" 'sudo pacman -R --noconfirm monarchy-identity' >/dev/null 2>&1
for f in system-auth omarchy-lock-password; do "${V[@]}" "cat /etc/pam.d/$f" | diff -q - fixtures/pam.d/$f >/dev/null && ok "after pacman -R: $f is stock again" || bad "after pacman -R: $f still edited"; done
"${V[@]}" 'grep -qE "^(passwd|group|shadow):.*sss" /etc/nsswitch.conf' && bad "nsswitch still has sss" || ok "nsswitch has no sss"
"${V[@]}" 'systemctl is-active monarchy-identity-reassert.path' | grep -qx active && bad "watcher still active" || ok "watcher stopped"
expect ALLOWED "local tester still fine after removal" sudo tester tester
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
