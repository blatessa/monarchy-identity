#!/bin/bash
# Build the real package, install it in the VM, and prove the packaged layout + pacman hook work.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$H/../.." && pwd)"; cd "$H"
SSHO=(-i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR)
V=(ssh "${SSHO[@]}" -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
rsync -a --exclude=.git --exclude=test "$R/" "$B/src/" && (cd "$B/src/packaging" && makepkg -f --nodeps >"$B/build.log" 2>&1) || { cat "$B/build.log" | tail; exit 1; }
PKG=$(ls "$B"/src/packaging/monarchy-identity-[0-9]*.pkg.tar.zst | head -1)
scp -q "${SSHO[@]}" -P 2222 "$PKG" tester@127.0.0.1:/home/tester/oi.pkg.tar.zst
./deploy.sh --fixtures >/dev/null
"${V[@]}" 'sudo pacman -U --noconfirm oi.pkg.tar.zst' >/dev/null 2>&1 && ok "package installs" || bad "package install"
"${V[@]}" 'sudo rm -rf ~/oi; /usr/bin/monarchy-identity providers' | grep -q sssd && ok "packaged CLI finds providers (no repo checkout)" || bad "packaged layout"
out=$(echo "$PW" | "${V[@]}" "sudo /usr/bin/monarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users --sudo-groups oi-admins" 2>&1)
[[ $out == *"enrolled in"* ]] && ok "enrol using packaged files" || { bad "enrol"; echo "$out" | sed 's/^/      /'; }
st() { "${V[@]}" '/usr/bin/monarchy-identity status --json'; }
[[ $(st) == *'"pam_system_auth":"true"'* ]] && ok "PAM edits present" || bad "PAM edits missing"

echo "[compliance check with the packaged files]"
"${V[@]}" 'test -f /usr/share/doc/monarchy-identity/policy.example.toml' && ok "example policy installed" || bad "example policy missing"
"${V[@]}" 'printf "require_enrolled = true\nrequire_self_heal = true\n" | sudo tee /tmp/oi-pol-ok.toml >/dev/null; printf "require_firewall = true\nrequire_tpm2 = true\n" | sudo tee /tmp/oi-pol-bad.toml >/dev/null'
"${V[@]}" 'MONARCHY_IDENTITY_POLICY=/tmp/oi-pol-ok.toml /usr/bin/monarchy-identity check' >/dev/null 2>&1 && ok "check exits 0 for a satisfied policy" || bad "check failed a satisfied policy"
"${V[@]}" 'MONARCHY_IDENTITY_POLICY=/tmp/oi-pol-bad.toml /usr/bin/monarchy-identity check' >/dev/null 2>&1; [[ $? == 1 ]] && ok "check exits 1 for a violated policy (VM has no TPM / firewall)" || bad "check did not exit 1"
"${V[@]}" 'MONARCHY_IDENTITY_POLICY=/nonexistent /usr/bin/monarchy-identity check' >/dev/null 2>&1; [[ $? == 2 ]] && ok "check exits 2 when the policy file is missing" || bad "missing policy exit code"
echo "[watcher is quiet when nothing changes (no self-trigger loop)]"
runs() { "${V[@]}" 'sudo journalctl -u monarchy-identity-reassert.service --no-pager -o cat | grep -c "Finished\|Succeeded"' ; }
sleep 6; r1=$(runs); sleep 12; r2=$(runs)
[[ $r1 == "$r2" ]] && ok "no reassert runs during 12s of idle (runs: $r2)" || bad "reassert storm: $r1 -> $r2"
echo "[login theme with a username field]"
"${V[@]}" 'test -f /usr/share/sddm/themes/monarchy-identity/Main.qml && test -L /usr/share/sddm/themes/monarchy-identity/logo.png' && ok "theme files installed (Main.qml + asset symlinks)" || bad "theme files missing"
"${V[@]}" 'grep -q "^Current=monarchy-identity" /etc/sddm.conf.d/zz-monarchy-identity-theme.conf' && ok "enrol selects the identity theme via zz- drop-in" || bad "theme drop-in missing"
[[ $(st) == *'"login_theme":"monarchy-identity"'* && $(st) == *'"username_field":true'* ]] && ok "status: effective theme monarchy-identity, username_field:true" || bad "status theme: $(st)"
"${V[@]}" 'sudo rm -f /etc/sddm.conf.d/zz-monarchy-identity-theme.conf'
for _ in $(seq 15); do sleep 1; [[ $(st) == *'"username_field":true'* ]] && break; done
[[ $(st) == *'"username_field":true'* ]] && ok "theme drop-in self-heals after deletion" || bad "theme drop-in not healed"
echo "[self-heal: root-owned path unit repairs drift with no manual step]"
"${V[@]}" 'systemctl is-active monarchy-identity-reassert.path' | grep -qx active && ok "watcher active after enrol" || bad "watcher not active"
[[ $(st) == *'"self_heal":true'* ]] && ok "status reports self_heal:true" || bad "self_heal flag"
"${V[@]}" 'sudo python3 -I /usr/share/monarchy-identity/lib/pamedit.py remove /etc/pam.d/system-auth'
for _ in $(seq 15); do sleep 1; [[ $(st) == *'"pam_system_auth":"true"'* ]] && break; done
[[ $(st) == *'"pam_system_auth":"true"'* ]] && ok "PAM edit auto-repaired within seconds" || bad "PAM not auto-repaired"
"${V[@]}" 'sudo sed -i -E "/^(passwd|group|shadow):/ s/[[:space:]]+sss\b//" /etc/nsswitch.conf'
for _ in $(seq 15); do sleep 1; [[ $(st) == *'"nss_sss":"true"'* ]] && break; done
[[ $(st) == *'"nss_sss":"true"'* ]] && ok "nsswitch auto-repaired" || bad "nsswitch not auto-repaired"
echo "[pacman hook: drift repaired by a package transaction (watcher paused so the hook is what we test)]"
"${V[@]}" 'sudo systemctl stop monarchy-identity-reassert.path'
"${V[@]}" 'sudo python3 -I /usr/share/monarchy-identity/lib/pamedit.py remove /etc/pam.d/system-auth; sudo sed -i -E "/^(passwd|group|shadow):/ s/[[:space:]]+sss\b//" /etc/nsswitch.conf'
[[ $(st) == *'"pam_system_auth":"false"'* && $(st) == *'"nss_sss":"false"'* ]] && ok "drift introduced (PAM + nsswitch)" || bad "could not introduce drift"
"${V[@]}" 'sudo pacman -S --noconfirm pambase' >/dev/null 2>&1
[[ $(st) == *'"pam_system_auth":"true"'* && $(st) == *'"nss_sss":"true"'* ]] && ok "hook repaired PAM + nsswitch after pambase transaction" || bad "hook did not repair: $(st)"
"${V[@]}" 'sudo journalctl -t monarchy-identity --no-pager -o cat | tail -3' | grep -q reasserted && ok "hook logged to journal" || bad "no journal entry"
echo "$PW" | "${V[@]}" 'sudo /usr/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
sleep 6
pam_stock() { for f in system-auth omarchy-lock-password; do "${V[@]}" "cat /etc/pam.d/$f" | diff -q - fixtures/pam.d/$f >/dev/null || return 1; done; }
pam_stock && ok "after leave: PAM stock and NOT re-added by the watcher (no race)" || bad "watcher re-added edits after leave"
"${V[@]}" 'test ! -e /etc/sddm.conf.d/zz-monarchy-identity-theme.conf' && ok "leave removed the theme drop-in" || bad "theme drop-in left behind"
"${V[@]}" 'systemctl is-active monarchy-identity-reassert.path' | grep -qx inactive && ok "watcher stopped by leave" || bad "watcher still active after leave"
"${V[@]}" 'sudo pacman -R --noconfirm monarchy-identity' >/dev/null 2>&1 && ok "package removes cleanly" || bad "package removal"
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
