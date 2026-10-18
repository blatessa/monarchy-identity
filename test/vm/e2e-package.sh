#!/bin/bash
# The real package: builds, installs, works without a repo checkout, its pacman hook repairs overwritten config, and
# removing it while enrolled takes sign-in back to stock. Needs DC + VM.
source "$(dirname "$0")/lib.sh"
fresh
st() { "${V[@]}" '/usr/bin/monarchy-identity status --json'; }

echo "[install and enroll from the package alone]"
./install-package.sh >/dev/null && ok "package builds and installs" || bad "package build/install"
"${V[@]}" 'rm -rf ~/oi'
out=$(echo "$PW" | "${V[@]}" "sudo /usr/bin/monarchy-identity enroll$(q $LAB --groups oi-laptop-users)" 2>&1); reset_locks
[[ $out == *"enrolled in"* ]] && ok "enroll with the packaged files" || { bad "enroll"; sed 's/^/      /' <<<"$out"; }
s=$(st); [[ $s == *'"pam_system_auth":"true"'* && $s == *'"username_field":true'* ]] && ok "sign-in and login theme in place" || bad "status: $s"
check "theme files and Omarchy asset links installed" "${V[@]}" 'test -f /usr/share/sddm/themes/monarchy-identity/Main.qml -a -L /usr/share/sddm/themes/monarchy-identity/logo.png'
expect ALLOWED "alice signs in" sddm alice "$PW"

echo "[pacman hook repairs overwritten config]"
"${V[@]}" 'sudo python3 -I /usr/share/monarchy-identity/lib/pamedit.py remove /etc/pam.d/system-auth; sudo sed -i -E "/^(passwd|group|shadow):/ s/[[:space:]]+sss\b//" /etc/nsswitch.conf'
[[ $(st) == *'"pam_system_auth":"false"'* ]] || bad "could not overwrite the config"
"${V[@]}" 'sudo pacman -S --noconfirm pambase' >/dev/null 2>&1
s=$(st); [[ $s == *'"pam_system_auth":"true"'* && $s == *'"nss_sss":"true"'* ]] && ok "repaired by the pambase transaction" || bad "not repaired: $s"
"${V[@]}" 'sudo python3 -I /usr/share/monarchy-identity/lib/pamedit.py remove /etc/pam.d/sddm'
[[ $(st) == *'"pam_sddm":"false"'* ]] || bad "could not overwrite the login screen's PAM"
"${V[@]}" 'sudo pacman -U --noconfirm oi.pkg.tar.zst' >/dev/null 2>&1
[[ $(st) == *'"pam_sddm":"true"'* ]] && ok "repaired by upgrading monarchy-identity itself (what a new version adds reaches enrolled machines)" || bad "own upgrade did not reassert: $(st)"

echo "[removing the package while enrolled]"
check "package removes" "${V[@]}" 'sudo pacman -R --noconfirm monarchy-identity >/dev/null 2>&1'
check "PAM back to stock" pam_stock
check "nsswitch has no sss" "${V[@]}" '! grep -qE "^(passwd|group|shadow):.*sss" /etc/nsswitch.conf'
check "login theme and autologin drop-ins gone" "${V[@]}" 'test -z "$(ls /etc/sddm.conf.d/zz-monarchy-identity* 2>/dev/null)"'
expect ALLOWED "tester (local) fine" sudo tester tester
dc computer delete 'OI-CLIENT$' >/dev/null   # removal has no directory credentials, so the account stays
result
