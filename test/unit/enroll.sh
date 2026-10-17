#!/bin/bash
# Enrollment options: --computer-name, --ou, password file and variable, --replace-computer-account, re-running after an
# enrollment stopped halfway, the login theme, and the user-level hook and widget installers.
source "$(dirname "$0")/lib.sh"
sandbox
G=(--groups oi-laptop-users)
joins() { grep -c '^net ads join' "$STUB_LOG"; }

echo "[--computer-name, --ou, --password-file with stdin closed]"
install -m 600 /dev/null "$T/oi.pw"; echo "$PW" > "$T/oi.pw"
OUT=$(unshare -r "$OIBIN" enroll --realm CORP.TEST --server dc.corp.test --admin Administrator "${G[@]}" --computer-name laptop-0042 \
  --ou OU=Laptops,DC=corp,DC=test --password-file "$T/oi.pw" </dev/null 2>&1); RC=$?
[[ $OUT == *"enrolled in CORP.TEST as LAPTOP-0042"* ]] && ok "enrolled as LAPTOP-0042" || { bad "enroll"; sed 's/^/      /' <<<"$OUT"; }
called 'createcomputer=Laptops' && ok "account created in the OU (createcomputer=Laptops)" || bad "no createcomputer"
[[ $(joins) == 2 ]] && ok "joined twice (the fresh-account quirk)" || bad "joins: $(joins)"
called 'net ads keytab create' && called 'kinit -k LAPTOP-0042$@CORP.TEST' && ok "keytab built with admin creds, machine key verified" || bad "keytab/kinit"
grep -q 'netbios name = LAPTOP-0042' "$T/etc/samba/smb.conf" && grep -q 'ldap_sasl_authid = LAPTOP-0042\$' "$T/etc/sssd/sssd.conf" \
  && grep -q 'ad_hostname = laptop-0042.corp.test' "$T/etc/sssd/sssd.conf" && ok "named after --computer-name, not the hostname" || bad "names in config"
oi policy show; [[ $OUT == *"LAPTOP-0042 in OU=Laptops"* ]] && ok "policy show reports name and OU" || bad "policy show: $OUT"
oi leave --admin Administrator --password-file "$T/oi.pw" </dev/null; called 'net ads leave -S dc.corp.test -U Administrator' && ok "leave --password-file deletes the account" || bad "leave"

echo "[password from OI_ADMIN_PASSWORD_FILE; wrong password in a file]"
sandbox; echo "$PW" > "$T/oi.pw"; chmod 600 "$T/oi.pw"
OUT=$(OI_ADMIN_PASSWORD_FILE=$T/oi.pw unshare -r "$OIBIN" enroll --realm CORP.TEST --server dc.corp.test "${G[@]}" </dev/null 2>&1)
[[ $OUT == *"enrolled in"* ]] && ok "OI_ADMIN_PASSWORD_FILE works" || { bad "env file"; sed 's/^/      /' <<<"$OUT"; }

echo "[--replace-computer-account]"
sandbox; STUB_COMPUTERS=OI-CLIENT
enroll "${G[@]}" --replace-computer-account
[[ $OUT == *"reusing existing computer account"* && $OUT == *"enrolled in"* ]] && ok "took over the existing account" || { bad "replace"; sed 's/^/      /' <<<"$OUT"; }

echo "[an enrollment that stopped before sign-in was switched on can simply be re-run]"
sandbox; STUB_COMPUTERS=OI-CLIENT; touch "$STUB_STATE/joined"   # the account exists and this machine is joined with it
enroll "${G[@]}"
[[ $OUT == *"reusing existing computer account"* && $OUT == *"enrolled in"* ]] && ok "re-run reuses this laptop's own account, no flag needed" || { bad "re-run"; sed 's/^/      /' <<<"$OUT"; }

echo "[enroll stops before touching sign-in when the machine key does not work]"
sandbox; before=$(cat "$T"/etc/pam.d/* "$T/etc/nsswitch.conf")
STUB_KINIT_FAIL=1 enroll "${G[@]}"
[[ $RC -ne 0 && $OUT == *"keytab does not authenticate"* ]] && ok "refused" || bad "kinit failure: $OUT"
[[ $(cat "$T"/etc/pam.d/* "$T/etc/nsswitch.conf") == "$before" ]] && ok "PAM and nsswitch untouched" || bad "sign-in changed"
[[ ! -e $MONARCHY_IDENTITY_CONF ]] && ok "no state recorded for an enrollment that did not finish" || bad "config.toml written"

echo "[login theme]"
sandbox; enroll "${G[@]}"
[[ $OUT == *"enrolled in"* && $OUT == *"login theme 'monarchy-identity' not installed"* ]] && ok "package files missing: enrolled, with a warning" || bad "no-theme: $OUT"
[[ ! -e $T/etc/sddm.conf.d/zz-monarchy-identity-theme.conf ]] && ok "no theme drop-in without the theme" || bad "theme drop-in"
sandbox; mkdir -p "$T/themes/monarchy-identity"; touch "$T/themes/monarchy-identity/Main.qml"
enroll "${G[@]}"; grep -qx 'Current=monarchy-identity' "$T/etc/sddm.conf.d/zz-monarchy-identity-theme.conf" && ok "theme selected" || bad "theme not selected"
oi leave; [[ ! -e $T/etc/sddm.conf.d/zz-monarchy-identity-theme.conf ]] && ok "leave removes it" || bad "theme left"
enroll "${G[@]}" --keep-login-theme; [[ ! -e $T/etc/sddm.conf.d/zz-monarchy-identity-theme.conf && $(cfg login_theme) == stock ]] && ok "--keep-login-theme" || bad "keep theme"

echo "[hooks and widget, as the desktop user]"
sandbox
H="$HOME/.config/omarchy"
oi_user install-hooks; check "post-update hook installed" test -x "$H/hooks/post-update.d/10-monarchy-identity-reassert"
oi_user remove-hooks; check "remove-hooks" test ! -e "$H/hooks/post-update.d/10-monarchy-identity-reassert"
oi_user install-widget; [[ $OUT == *"installed monarchy-identity.status"* ]] && check "widget installed" test -f "$H/plugins/monarchy-identity.status/Panel.qml" || bad "install-widget: $OUT"
oi_user remove-widget; check "remove-widget" test ! -e "$H/plugins/monarchy-identity.status"
oi install-hooks; [[ $OUT == *"not root"* ]] && ok "install-hooks refuses root" || bad "hooks as root: $OUT"
oi install-widget; [[ $OUT == *"not root"* ]] && ok "install-widget refuses root" || bad "widget as root: $OUT"
result
