#!/bin/bash
# The real package: builds, installs, works without a repo checkout, its pacman hook repairs overwritten config, and
# removing it while enrolled takes sign-in back to stock. Needs DC + VM. The same for Entra ID with the himmelblau
# package, when a test tenant is configured (ENTRA_LAB_ENV, docs/dev/testing.md); without one that part is skipped.
source "$(dirname "$0")/lib.sh"
fresh
st() { "${V[@]}" '/usr/bin/monarchy-identity status --json'; }

echo "[install and enroll from the package alone]"
./install-package.sh >/dev/null && ok "package builds and installs" || bad "package build/install"
"${V[@]}" 'rm -rf ~/oi'
out=$(echo "$PW" | "${V[@]}" "sudo /usr/bin/monarchy-identity enroll$(q $LAB --groups oi-laptop-users --sudo-groups oi-admins)" 2>&1); reset_locks
[[ $out == *"enrolled in"* ]] && ok "enroll with the packaged files" || { bad "enroll"; sed 's/^/      /' <<<"$out"; }
s=$(st); [[ $s == *'"pam_system_auth":"true"'* && $s == *'"username_field":true'* ]] && ok "sign-in and login theme in place" || bad "status: $s"
DROPINS="/etc/sudoers.d/50-monarchy-identity /etc/sudoers.d/51-monarchy-identity-theme /etc/polkit-1/rules.d/49-monarchy-identity.rules"
check "sudoers drop-ins and polkit rule in place" "${V[@]}" "sudo ls $DROPINS >/dev/null"
check "theme files and Omarchy asset links installed" "${V[@]}" 'test -f /usr/share/sddm/themes/monarchy-identity/Main.qml -a -f /usr/share/sddm/themes/monarchy-identity/reasons.js -a -L /usr/share/sddm/themes/monarchy-identity/logo.png'
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
check "sudoers drop-ins and polkit rule gone" "${V[@]}" "for f in $DROPINS; do sudo test ! -e \$f || exit 1; done"
check "login theme and autologin drop-ins gone" "${V[@]}" 'test -z "$(ls /etc/sddm.conf.d/zz-monarchy-identity* 2>/dev/null)"'
expect ALLOWED "tester (local) fine" sudo tester tester
dc computer delete 'OI-CLIENT$' >/dev/null   # removal has no directory credentials, so the account stays

echo "[Entra ID from the package]"
if entra_lab; then
  SECRET=/root/entra-secret
  ecli() { "${V[@]}" "sudo /usr/bin/monarchy-identity $*" 2>&1; }
  E="enroll entra --tenant $ENTRA_TENANT --client-id $ENTRA_CLIENT_ID --password-file $SECRET --groups linux-users"
  trap '"${V[@]}" "sudo rm -f $SECRET"; himmelblau_install; entra_devices_cleanup' EXIT
  ./install-package.sh >/dev/null && "${V[@]}" 'sudo pacman -R --noconfirm himmelblau' >/dev/null 2>&1
  printf '%s\n' "$ENTRA_CLIENT_SECRET" | "${V[@]}" "sudo install -m 600 /dev/stdin $SECRET"
  entra_devices_cleanup
  out=$(ecli $E)
  [[ $out == *"sudo pacman -S himmelblau"* ]] && pam_stock && ok "without himmelblau: refused with the install line, nothing changed" || bad "no himmelblau: $out"

  himmelblau_install && out=$(ecli $E)
  [[ $out == *"enrolled in $ENTRA_TENANT"* ]] && ok "enroll entra with the packaged files" || { bad "enroll entra"; sed 's/^/      /' <<<"$out"; }
  expect ALLOWED "bob signs in (registers the device)" login "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD" --session

  "${V[@]}" 'sudo python3 -I /usr/share/monarchy-identity/lib/pamedit.py remove /etc/pam.d/system-auth; sudo sed -i -E "/^(passwd|group|shadow):/ s/[[:space:]]+himmelblau\b//" /etc/nsswitch.conf; sudo systemctl stop himmelblaud'
  [[ $(st) == *'"nss_himmelblau":"false"'* ]] || bad "could not overwrite the config"
  "${V[@]}" 'sudo pacman -U --noconfirm ~/himmelblau.pkg.tar.zst' >/dev/null 2>&1
  s=$(st); [[ $s == *'"pam_system_auth":"true"'* && $s == *'"nss_himmelblau":"true"'* && $s == *'"himmelblaud_active":"true"'* ]] \
    && ok "repaired by the himmelblau transaction" || bad "not repaired: $s"

  # The client gone while enrolled (removed by hand): its PAM and NSS entries are skipped, local accounts unaffected.
  # pacman doesn't stop a removed package's daemon, so stop it as a reboot would.
  "${V[@]}" 'sudo systemctl stop himmelblaud himmelblaud-tasks; sudo pacman -R --noconfirm himmelblau' >/dev/null 2>&1
  expect ALLOWED "himmelblau removed while enrolled: tester (local) signs in" login tester tester
  expect ALLOWED "  ... and gets sudo" sudo tester tester
  [[ $(st) == *'"himmelblaud_active":"false"'* ]] && ok "  ... status says so" || bad "status with himmelblau gone: $(st)"
  himmelblau_install
  expect ALLOWED "himmelblau back: bob signs in again" login "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD"

  check "package removes while enrolled with Entra" "${V[@]}" 'sudo pacman -R --noconfirm monarchy-identity >/dev/null 2>&1'
  pam_stock && "${V[@]}" '! grep -q himmelblau /etc/nsswitch.conf && ! test -e /etc/himmelblau/himmelblau.conf.d/50-monarchy-identity.conf && ! systemctl is-active --quiet himmelblaud' \
    && ok "PAM stock, nsswitch clean, himmelblau config gone, daemon stopped" || bad "leftovers after removing the package"
  expect ALLOWED "tester (local) fine" sudo tester tester
fi
result
