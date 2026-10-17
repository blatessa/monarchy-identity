#!/bin/bash
# MDM/Ansible-style use: no stdin, password from a 0600 file or $OI_ADMIN_PASSWORD_FILE. Needs DC + VM.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
A="--realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users"
st() { "${V[@]}" '~/oi/bin/monarchy-identity status --json'; }
./deploy.sh --fixtures >/dev/null
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
"${V[@]}" "sudo install -m 600 /dev/null /root/oi.pw && echo '$PW' | sudo tee /root/oi.pw >/dev/null; sudo install -m 644 /dev/null /tmp/oi-open.pw && echo '$PW' | sudo tee /tmp/oi-open.pw >/dev/null"

echo "[password file]"
out=$("${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $A --password-file /tmp/oi-open.pw </dev/null" 2>&1)
[[ $out == *"accessible by group/other"* ]] && ok "world-readable password file refused" || bad "not refused: $out"
[[ $(st) == *'"enrolled":false'* ]] && ok "nothing changed after refusal" || bad "state changed"
out=$("${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $A --password-file /root/oi.pw </dev/null" 2>&1)
[[ $out == *"enrolled in"* ]] && ok "enroll via --password-file, stdin closed" || { bad "enroll via file"; echo "$out" | sed 's/^/      /'; }
out=$("${V[@]}" "sudo ~/oi/bin/monarchy-identity leave --admin Administrator --password-file /root/oi.pw </dev/null" 2>&1)
[[ $(docker exec oi-test-dc samba-tool computer list | grep -c OI-CLIENT) -eq 0 ]] && ok "leave --password-file removed the computer account" || bad "computer account left: $out"

echo "[environment variable]"
out=$("${V[@]}" "sudo OI_ADMIN_PASSWORD_FILE=/root/oi.pw ~/oi/bin/monarchy-identity enroll sssd $A </dev/null" 2>&1)
[[ $out == *"enrolled in"* ]] && ok "enroll via OI_ADMIN_PASSWORD_FILE" || { bad "enroll via env"; echo "$out" | sed 's/^/      /'; }
out=$("${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $A </dev/null" 2>&1)
"${V[@]}" "sudo OI_ADMIN_PASSWORD_FILE=/root/oi.pw ~/oi/bin/monarchy-identity leave --admin Administrator </dev/null" >/dev/null 2>&1
out=$("${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $A </dev/null" 2>&1)
[[ $out == *"password must be given"* ]] && ok "no password source -> clear error, no hang" || bad "unexpected: $out"

echo "[install-hooks]"
"${V[@]}" '~/oi/bin/monarchy-identity install-hooks' | grep -q installed && ok "install-hooks (as user)" || bad "install-hooks"
"${V[@]}" 'test -x ~/.config/omarchy/hooks/post-update.d/10-monarchy-identity-reassert' && ok "hook present and executable" || bad "hook missing"
"${V[@]}" '~/oi/bin/monarchy-identity remove-hooks' >/dev/null; "${V[@]}" 'test -e ~/.config/omarchy/hooks/post-update.d/10-monarchy-identity-reassert' && bad "hook not removed" || ok "remove-hooks"
"${V[@]}" '~/oi/bin/monarchy-identity install-widget' | grep -q 'installed monarchy-identity.status' && ok "install-widget (as user) copies the widget into ~/.config/omarchy/plugins" || bad "install-widget"
"${V[@]}" 'test -f ~/.config/omarchy/plugins/monarchy-identity.status/manifest.json && test -f ~/.config/omarchy/plugins/monarchy-identity.status/Panel.qml' && ok "widget files present" || bad "widget files missing"
"${V[@]}" '~/oi/bin/monarchy-identity remove-widget' >/dev/null; "${V[@]}" 'test ! -e ~/.config/omarchy/plugins/monarchy-identity.status' && ok "remove-widget" || bad "remove-widget"
"${V[@]}" 'sudo ~/oi/bin/monarchy-identity install-widget' 2>&1 | grep -q 'not root' && ok "install-widget refuses root" || bad "install-widget as root"
"${V[@]}" 'sudo ~/oi/bin/monarchy-identity install-hooks' 2>&1 | grep -q 'not root' && ok "install-hooks refuses root" || bad "install-hooks as root"
"${V[@]}" 'sudo rm -f /root/oi.pw /tmp/oi-open.pw'
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
