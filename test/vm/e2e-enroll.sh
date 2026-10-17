#!/bin/bash
# Enrollment options: --computer-name, --ou, password file and environment variable, --replace-computer-account,
# re-running after an enrollment stopped halfway, and the user-level hook and widget installers. Needs DC + VM.
source "$(dirname "$0")/lib.sh"
trap 'dc ou delete "OU=Laptops,DC=corp,DC=test" >/dev/null; for c in "OI-CLIENT\$" "LAPTOP-0042\$"; do dc computer delete "$c" >/dev/null; done; "${V[@]}" "sudo rm -f /root/oi.pw" >/dev/null 2>&1' EXIT
fresh
"${V[@]}" "sudo install -m 600 /dev/null /root/oi.pw && echo '$PW' | sudo tee /root/oi.pw >/dev/null"
dc ou create "OU=Laptops,DC=corp,DC=test" >/dev/null

echo "[--computer-name, --ou, --password-file with stdin closed]"
out=$("${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll$(q $LAB --groups oi-laptop-users --computer-name LAPTOP-0042 --ou OU=Laptops,DC=corp,DC=test --password-file /root/oi.pw) </dev/null" 2>&1)
[[ $out == *"enrolled in CORP.TEST as LAPTOP-0042"* ]] && ok "enrolled as LAPTOP-0042" || { bad "enroll"; sed 's/^/      /' <<<"$out"; }
dn=$(dc computer show 'LAPTOP-0042$' | sed -n 's/^dn: //p')
[[ $dn == "CN=LAPTOP-0042,OU=Laptops,DC=corp,DC=test" ]] && ok "account created in the OU" || bad "DN: $dn"
has_account 'OI-CLIENT$' && bad "hostname account also created" || ok "no account named after the hostname"
reset_locks; expect ALLOWED "alice signs in" sddm alice "$PW"
[[ $(cli policy show) == *"LAPTOP-0042 in OU=Laptops"* ]] && ok "policy show reports name and OU" || bad "policy show: $(cli policy show)"
"${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator --password-file /root/oi.pw </dev/null' >/dev/null 2>&1
has_account 'LAPTOP-0042$' && bad "account left behind" || ok "leave --password-file deleted the account"

echo "[--replace-computer-account, OI_ADMIN_PASSWORD_FILE]"
dc computer create OI-CLIENT >/dev/null
out=$("${V[@]}" "sudo OI_ADMIN_PASSWORD_FILE=/root/oi.pw ~/oi/bin/monarchy-identity enroll$(q $LAB --groups oi-laptop-users --replace-computer-account) </dev/null" 2>&1)
[[ $out == *"enrolled in"* ]] && ok "took over the existing account" || { bad "replace"; sed 's/^/      /' <<<"$out"; }

echo "[an enrollment that stopped before sign-in was switched on can simply be re-run]"
"${V[@]}" 'sudo python3 -I ~/oi/lib/pamedit.py remove /etc/pam.d/system-auth; printf "provider = \"local\"\n" | sudo tee /etc/monarchy-identity/config.toml >/dev/null'
out=$(enroll --groups oi-laptop-users)
[[ $out == *"reusing existing computer account"* && $out == *"enrolled in"* ]] && ok "re-run reuses this laptop's own account, no flag needed" || { bad "re-run"; sed 's/^/      /' <<<"$out"; }
expect ALLOWED "alice signs in" system-auth alice "$PW"
leave

echo "[hooks and widget, as the desktop user]"
[[ $(cli install-hooks) == *installed* ]] && check "post-update hook installed" "${V[@]}" 'test -x ~/.config/omarchy/hooks/post-update.d/10-monarchy-identity-reassert' || bad "install-hooks"
cli remove-hooks >/dev/null; check "remove-hooks" "${V[@]}" 'test ! -e ~/.config/omarchy/hooks/post-update.d/10-monarchy-identity-reassert'
[[ $(cli install-widget) == *"installed monarchy-identity.status"* ]] && check "widget installed" "${V[@]}" 'test -f ~/.config/omarchy/plugins/monarchy-identity.status/Panel.qml' || bad "install-widget"
cli remove-widget >/dev/null; check "remove-widget" "${V[@]}" 'test ! -e ~/.config/omarchy/plugins/monarchy-identity.status'
[[ $(scli install-hooks) == *"not root"* && $(scli install-widget) == *"not root"* ]] && ok "both refuse root" || bad "ran as root"
result
