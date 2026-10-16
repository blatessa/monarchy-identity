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
PKG=$(ls "$B"/src/packaging/omarchy-identity-[0-9]*.pkg.tar.zst | head -1)
scp -q "${SSHO[@]}" -P 2222 "$PKG" tester@127.0.0.1:/home/tester/oi.pkg.tar.zst
./deploy.sh --fixtures >/dev/null
"${V[@]}" 'sudo pacman -U --noconfirm oi.pkg.tar.zst' >/dev/null 2>&1 && ok "package installs" || bad "package install"
"${V[@]}" 'sudo rm -rf ~/oi; /usr/bin/omarchy-identity providers' | grep -q sssd && ok "packaged CLI finds providers (no repo checkout)" || bad "packaged layout"
out=$(echo "$PW" | "${V[@]}" "sudo /usr/bin/omarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users" 2>&1)
[[ $out == *"enrolled in"* ]] && ok "enrol using packaged files" || { bad "enrol"; echo "$out" | sed 's/^/      /'; }
st() { "${V[@]}" '/usr/bin/omarchy-identity status --json'; }
[[ $(st) == *'"pam_system_auth":"true"'* ]] && ok "PAM edits present" || bad "PAM edits missing"

echo "[pacman hook: drift repaired by a package transaction]"
"${V[@]}" 'sudo python3 -I /usr/share/omarchy-identity/lib/pamedit.py remove /etc/pam.d/system-auth; sudo sed -i -E "/^(passwd|group|shadow):/ s/[[:space:]]+sss\b//" /etc/nsswitch.conf'
[[ $(st) == *'"pam_system_auth":"false"'* && $(st) == *'"nss_sss":"false"'* ]] && ok "drift introduced (PAM + nsswitch)" || bad "could not introduce drift"
"${V[@]}" 'sudo pacman -S --noconfirm pambase' >/dev/null 2>&1
[[ $(st) == *'"pam_system_auth":"true"'* && $(st) == *'"nss_sss":"true"'* ]] && ok "hook repaired PAM + nsswitch after pambase transaction" || bad "hook did not repair: $(st)"
"${V[@]}" 'sudo journalctl -t omarchy-identity --no-pager -o cat | tail -3' | grep -q reasserted && ok "hook logged to journal" || bad "no journal entry"
echo "$PW" | "${V[@]}" 'sudo /usr/bin/omarchy-identity leave --admin Administrator' >/dev/null 2>&1
"${V[@]}" 'sudo pacman -R --noconfirm omarchy-identity' >/dev/null 2>&1 && ok "package removes cleanly" || bad "package removal"
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
