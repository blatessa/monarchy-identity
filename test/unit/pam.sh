#!/bin/bash
# The edits to PAM, nsswitch and SDDM, on Omarchy's real files: apply, remove, idempotent, skip counts, only marked
# files removed on `leave`, autologin merge order. Whether the stack then authenticates is the lab's job.
source "$(dirname "$0")/lib.sh"
sandbox
PE=(python3 -I "$REPO/lib/pamedit.py")
SSS=(pam_sss.so auth=forward_pass)   # what the ad provider declares in providers/ad/pam.conf
SA=$T/etc/pam.d/system-auth LP=$T/etc/pam.d/omarchy-lock-password
rule() { grep -F -- "$2" "$1" | head -1 | tr -s ' '; }
sddm_conf() { (source "$REPO/lib/common.sh"; sddm_conf_value "$@"); }

echo "[pamedit on Omarchy's files]"
for f in system-auth omarchy-lock-password; do
  stock=$(cat "$T/etc/pam.d/$f"); "${PE[@]}" apply "$T/etc/pam.d/$f" "${SSS[@]}"; once=$(cat "$T/etc/pam.d/$f")
  [[ $once != "$stock" ]] && ok "$f: apply changes it" || bad "$f: apply did nothing"
  "${PE[@]}" apply "$T/etc/pam.d/$f" "${SSS[@]}"; [[ $(cat "$T/etc/pam.d/$f") == "$once" ]] && ok "$f: apply twice is the same as once" || bad "$f: not idempotent"
  "${PE[@]}" check "$T/etc/pam.d/$f" && ok "$f: check sees the edit" || bad "$f: check"
  "${PE[@]}" remove "$T/etc/pam.d/$f"; [[ $(cat "$T/etc/pam.d/$f") == "$stock" ]] && ok "$f: remove restores the file byte for byte" || bad "$f: remove"
  ! "${PE[@]}" check "$T/etc/pam.d/$f" && ok "$f: check is false after remove" || bad "$f: check after remove"
done
"${PE[@]}" apply "$SA" "${SSS[@]}"
[[ $(rule "$SA" 'pam_sss.so forward_pass') == "-auth [success=3 perm_denied=die acct_expired=die default=ignore] pam_sss.so forward_pass" ]] && ok "auth skips systemd_home, unix and faillock authfail (success=3); the directory's \"can't\" ends it" || bad "auth skip: $(rule "$SA" forward_pass)"
[[ $(rule "$SA" 'module_unknown=ignore') == "-account [success=2 user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad] pam_sss.so" ]] && ok "account: unknown/unavailable ignored, skips systemd_home and unix" || bad "account rule"
grep -qE '^-password +\[success=2 default=ignore\] +pam_sss.so' "$SA" && ok "password skip count" || bad "password rule"
grep -qx 'session    required   pam_mkhomedir.so umask=0077' "$SA" && ok "pam_mkhomedir at the top of session" || bad "mkhomedir"
! grep -E '^[^#]*pam_sss' "$SA" | grep -vq '^-' && ok "every pam_sss rule is -prefixed (safe when the module is missing)" || bad "a pam_sss rule is not -prefixed"
[[ $(grep -c 'BEGIN monarchy-identity' "$SA") == 4 ]] && ok "four marked blocks" || bad "blocks: $(grep -c BEGIN "$SA")"
for t in auth account password session; do   # a local account sharing a name with a directory user stays local
  [[ $(grep -E -B1 "^-$t .*pam_sss\.so" "$SA" | head -1 | tr -s ' ') == "-$t [success=1 default=ignore] pam_localuser.so" ]] \
    || { bad "$t: pam_localuser does not skip pam_sss for local accounts"; continue; }
  ok "$t: local accounts skip pam_sss"
done
"${PE[@]}" remove "$SA"
echo "[another provider's module gets the same rules, with its own arguments]"
"${PE[@]}" apply "$SA" pam_other.so auth=use_first_pass account='a b'
[[ $(rule "$SA" 'pam_other.so use_first_pass') == "-auth [success=3 perm_denied=die acct_expired=die default=ignore] pam_other.so use_first_pass" ]] && ok "auth rule and skip count" || bad "auth: $(rule "$SA" pam_other)"
[[ $(rule "$SA" 'module_unknown=ignore') == *"default=bad] pam_other.so a b" ]] && ok "account rule keeps the ignore mappings" || bad "account: $(rule "$SA" module_unknown)"
grep -qE '^-password +\[success=2 default=ignore\] +pam_other.so$' "$SA" && grep -qx -- '-session   optional   pam_other.so' "$SA" && ok "password and session rules" || bad "password/session"
! grep -E '^[^#]*pam_other' "$SA" | grep -vq '^-' && ! grep -q pam_sss "$SA" && ok "every rule -prefixed, no pam_sss" || bad "rules"
"${PE[@]}" remove "$SA"; cmp -s "$SA" "$FIX/pam.d/system-auth" && ok "remove needs no module name" || bad "remove"
echo "[a module that makes home directories itself: no pam_mkhomedir]"
"${PE[@]}" apply --no-mkhomedir "$SA" pam_other.so; once=$(cat "$SA")
! grep -q pam_mkhomedir "$SA" && grep -qx -- '-session   optional   pam_other.so' "$SA" && ok "session rule without pam_mkhomedir" || bad "mkhomedir: $(grep -A3 BEGIN "$SA" | grep session)"
"${PE[@]}" apply --no-mkhomedir "$SA" pam_other.so; [[ $(cat "$SA") == "$once" ]] && ok "apply twice is the same as once" || bad "not idempotent"
"${PE[@]}" apply "$SA" pam_other.so; grep -q pam_mkhomedir "$SA" && ok "applying with it again adds it back" || bad "mkhomedir not re-added"
"${PE[@]}" remove "$SA"; cmp -s "$SA" "$FIX/pam.d/system-auth" && ok "remove restores the file byte for byte" || bad "remove"
echo "[a module that aborts once when the directory becomes unreachable: asked again only after an abort]"
"${PE[@]}" apply --retry-on-abort "$SA" pam_other.so auth=x; once=$(cat "$SA")
[[ $(rule "$SA" 'pam_localuser.so' ) == "-auth [success=2 default=ignore] pam_localuser.so" ]] && ok "local accounts skip both tries" || bad "guard: $(rule "$SA" pam_localuser)"
[[ $(rule "$SA" 'abort=ignore') == "-auth [success=4 abort=ignore perm_denied=die acct_expired=die default=1] pam_other.so x" ]] && ok "first try: success skips the retry too; anything but abort skips only the retry" || bad "first: $(rule "$SA" abort=ignore)"
[[ $(grep -F 'pam_other.so x' "$SA" | sed -n 2p | tr -s ' ') == "-auth [success=3 perm_denied=die acct_expired=die default=ignore] pam_other.so x" ]] && ok "the retry is the plain rule" || bad "retry rule"
"${PE[@]}" apply --retry-on-abort "$SA" pam_other.so auth=x; [[ $(cat "$SA") == "$once" ]] && ok "apply twice is the same as once" || bad "not idempotent"
"${PE[@]}" remove "$SA"; cmp -s "$SA" "$FIX/pam.d/system-auth" && ok "remove restores the file byte for byte" || bad "remove"
echo "[a module or argument that could add a PAM line is refused, file untouched]"
refuse() { local what=$1; shift   # refuse WHAT MODULE [ARGS]: apply must fail and leave the file as it was
  if "${PE[@]}" apply "$SA" "$@" 2>/dev/null; then bad "accepted $what"
  elif cmp -s "$SA" "$FIX/pam.d/system-auth"; then ok "refused $what"; else bad "$what changed the file"; fi; }
refuse "an argument with a newline"  pam_x.so auth=$'a\nauth sufficient pam_permit.so'
refuse "a control field in an argument" pam_x.so 'auth=[success=done]'
refuse "a module path"               ../pam_x.so
refuse "a module name with a space"  'pam_x.so; x'
refuse "an unknown stack type"       pam_x.so bogus=1
refuse "no module at all"
echo "[a plain stack (no systemd_home, no faillock) still gets a correct skip count]"
printf '#%%PAM-1.0\nauth required pam_unix.so\naccount required pam_unix.so\nsession required pam_unix.so\n' > "$T/plain"
"${PE[@]}" apply "$T/plain" "${SSS[@]}"; grep -qF -- '-auth      [success=1 perm_denied=die acct_expired=die default=ignore]  pam_sss.so forward_pass' "$T/plain" && ok "plain stack: success=1" || bad "plain: $(cat "$T/plain")"
echo "[a file with no pam_unix at all is left alone]"
printf '#%%PAM-1.0\nauth required pam_deny.so\n' > "$T/odd"; cp "$T/odd" "$T/odd.0"; "${PE[@]}" apply "$T/odd" "${SSS[@]}"; cmp -s "$T/odd" "$T/odd.0" && ok "unchanged" || bad "odd file modified"
echo "[permissions survive an edit]"
chmod 0640 "$SA"; "${PE[@]}" apply "$SA" "${SSS[@]}"; [[ $(stat -c %a "$SA") == 640 ]] && ok "mode kept" || bad "mode changed"; "${PE[@]}" remove "$SA"

echo "[the login screen's service: an expired password is let through to be changed]"
SD=$T/etc/pam.d/sddm H=/usr/share/monarchy-identity/lib/password-expired
"${PE[@]}" greeter "$SD" "$H"; once=$(cat "$SD")
"${PE[@]}" greeter "$SD" "$H"; [[ $(cat "$SD") == "$once" ]] && ok "apply twice is the same as once" || bad "greeter not idempotent"
grep -A2 -E '^auth +include +system-login' "$SD" | tail -1 | grep -qx -- "-auth      optional  pam_exec.so quiet expose_authtok $H" \
  && ok "auth: the re-check runs right after the real password check, optional" || bad "auth rule: $(cat "$SD")"
[[ $(grep -E '^-?account' "$SD" | head -1) == "-account   [success=done default=ignore]  pam_exec.so quiet $H" ]] \
  && ok "account: first, done only on success, otherwise ignored" || bad "account rule: $(grep account "$SD")"
! grep -E '^[^#]*pam_exec' "$SD" | grep -vq '^-' && ok "both rules -prefixed" || bad "a pam_exec rule is not -prefixed"
"${PE[@]}" remove "$SD"; cmp -s "$SD" "$FIX/pam.d/sddm" && ok "remove restores the file byte for byte" || bad "greeter remove"
"${PE[@]}" greeter "$SD" 'x; auth sufficient pam_permit.so' 2>/dev/null; cmp -s "$SD" "$FIX/pam.d/sddm" && ok "refused a helper that isn't a plain absolute path" || bad "accepted a bad helper"
printf 'auth required pam_unix.so\naccount required pam_unix.so\n' > "$T/plain2"; cp "$T/plain2" "$T/plain2.0"
"${PE[@]}" greeter "$T/plain2" "$H"; cmp -s "$T/plain2" "$T/plain2.0" && ok "a service that doesn't include system-login is left alone" || bad "edited an unknown sddm file"

echo "[the login screen's service: more than a password, the directory asked once]"
H2=/usr/share/monarchy-identity/lib/login-steps
"${PE[@]}" login-steps "$SD" "$H2"; once=$(cat "$SD")
"${PE[@]}" login-steps "$SD" "$H2"; [[ $(cat "$SD") == "$once" ]] && ok "apply twice is the same as once" || bad "login-steps not idempotent"
[[ $(grep -B1 -E '^auth +include +system-login' "$SD" | head -1) == "# END monarchy-identity" ]] \
  && grep -qxF -- "-auth      [success=done default=ignore]  pam_exec.so quiet stdout expose_authtok $H2" "$SD" \
  && grep -qxF -- "-auth      [success=die default=ignore]  pam_exec.so quiet $H2 refused" "$SD" \
  && ok "auth: before the normal stack, its output shown, done when signed in, failing at once when refused" || bad "auth rules: $(cat "$SD")"
[[ $(grep -cE '^-?account' "$SD") == 1 ]] && ok "account: untouched (the directory decides who may sign in, as everywhere)" || bad "account rules: $(grep account "$SD")"
! grep -E '^[^#]*pam_exec' "$SD" | grep -vq '^-' && ok "both rules -prefixed" || bad "a pam_exec rule is not -prefixed"
"${PE[@]}" greeter "$SD" "$H"; ! grep -q login-steps "$SD" && grep -q password-expired "$SD" && ok "switching to the expired-password rules replaces them" || bad "both sets"
"${PE[@]}" login-steps "$SD" "$H2"; "${PE[@]}" remove "$SD"; cmp -s "$SD" "$FIX/pam.d/sddm" && ok "remove restores the file byte for byte" || bad "login-steps remove"
"${PE[@]}" login-steps "$SD" 'x; auth sufficient pam_permit.so' 2>/dev/null; cmp -s "$SD" "$FIX/pam.d/sddm" && ok "refused a helper that isn't a plain absolute path" || bad "accepted a bad helper"

echo "[the login screen's service: a locked account says so]"
FL="-auth      [auth_err=die default=ignore]  pam_faillock.so preauth deny=10 unlock_time=120"
"${PE[@]}" greeter "$SD" "$H"; [[ $(grep -E '^-?auth' "$SD" | head -1) == "$FL" ]] \
  && ok "first: Omarchy's faillock check with its limits, not silent; ends the sign-in only when locked" || bad "faillock rule: $(grep -E '^-?auth' "$SD" | head -1)"
"${PE[@]}" login-steps "$SD" "$H2"; [[ $(grep -E '^-?auth' "$SD" | head -2 | tail -1) == *"$H2" && $(grep -E '^-?auth' "$SD" | head -1) == "$FL" ]] \
  && ok "ahead of login-steps too (signed in there, the stack is done)" || bad "login-steps order: $(cat "$SD")"
"${PE[@]}" apply "$SA" "${SSS[@]}"; "${PE[@]}" login-steps "$SD" "$H2"; [[ $(grep -c pam_faillock "$SD") == 1 ]] && ok "limits read from system-auth as Omarchy wrote it, edited or not" || bad "faillock with an edited system-auth"
"${PE[@]}" remove "$SA"; "${PE[@]}" remove "$SD"; cmp -s "$SD" "$FIX/pam.d/sddm" && ok "remove restores the file byte for byte" || bad "remove"
cp "$SA" "$T/sa.0"; sed -i '/pam_faillock.so preauth/d' "$SA"; "${PE[@]}" greeter "$SD" "$H"; ! grep -q pam_faillock "$SD" && ok "no faillock check in system-auth: none added" || bad "faillock added without one"
"${PE[@]}" remove "$SD"; cp "$T/sa.0" "$SA"

echo "[enroll and leave]"
enroll --groups oi-laptop-users; [[ $OUT == *"enrolled in"* ]] || { bad "enroll: $OUT"; }
has_pam system-auth && has_pam omarchy-lock-password && ok "both Omarchy services edited" || bad "PAM not applied"
for f in login sudo su sddm-greeter sddm-autologin; do ! has_pam "$f" && continue; bad "$f was edited"; done; ok "other services (sudo, login, su, the greeter's own) untouched; they include system-auth"
has_pam sddm && ok "the login screen's service has the expired-password rules" || bad "sddm not edited"
grep -qx 'account  required  pam_sss.so' "$T/etc/pam.d/monarchy-identity-expired" && grep -qF "# managed by monarchy-identity" "$T/etc/pam.d/monarchy-identity-expired" \
  && ok "the re-check service: the provider's module only, marked as ours" || bad "expired service: $(cat "$T/etc/pam.d/monarchy-identity-expired" 2>&1)"
[[ $(sddm_conf Wayland SessionCommand) == "$REPO/lib/sddm-session" && $(sddm_conf X11 SessionCommand) == "$REPO/lib/sddm-session" ]] \
  && ok "SDDM's session command is ours, Wayland and X11 (effective after Omarchy's drop-ins)" || bad "session command: $(sddm_conf Wayland SessionCommand)"
grep -qE '^passwd:.*files sss systemd' "$T/etc/nsswitch.conf" && grep -qE '^group:.*files sss ' "$T/etc/nsswitch.conf" && grep -qE '^shadow:.*files sss' "$T/etc/nsswitch.conf" && ok "nsswitch: sss after files for passwd, group, shadow" || bad "nsswitch: $(cat "$T/etc/nsswitch.conf")"
grep -q '^hosts: files dns$' "$T/etc/nsswitch.conf" && ok "hosts line untouched" || bad "hosts changed"
oi reassert; [[ $(grep -c sss "$T/etc/nsswitch.conf") == 3 && $(grep -c 'BEGIN monarchy' "$SA") == 4 ]] && ok "reassert is idempotent" || bad "reassert duplicated edits"
echo "[reassert repairs what an update overwrote]"
cp "$FIX/pam.d/system-auth" "$SA"; cp "$FIX/pam.d/sddm" "$T/etc/pam.d/sddm"; sed -i -E '/^(passwd|group|shadow):/ s/[[:space:]]+sss\b//' "$T/etc/nsswitch.conf"
oi reassert; has_pam system-auth && has_pam sddm && grep -qE '^passwd:.*sss' "$T/etc/nsswitch.conf" && ok "PAM and nsswitch back" || bad "reassert: $OUT"
echo "[leave removes only what is marked]"
touch "$T/sss/db/cache.ldb" "$T/sss/mc/passwd"
printf '[libdefaults]\n' > "$T/etc/krb5.conf"          # someone replaced our krb5.conf with their own: not ours to delete
oi leave
for f in system-auth omarchy-lock-password sddm; do cmp -s "$FIX/pam.d/$f" "$T/etc/pam.d/$f" && ok "$f back to stock" || bad "$f differs from stock"; done
[[ ! -e $T/etc/pam.d/monarchy-identity-expired && ! -e $T/etc/sddm.conf.d/zz-monarchy-identity-session.conf ]] && ok "the re-check service and the session command removed" || bad "greeter files left"
grep -qE '^(passwd|group|shadow):.*sss' "$T/etc/nsswitch.conf" && bad "sss still in nsswitch" || ok "nsswitch has no sss"
[[ ! -e $T/etc/sssd/sssd.conf && ! -e $T/etc/samba/smb.conf && ! -e $T/etc/krb5.keytab ]] && ok "sssd.conf, smb.conf and the keytab removed" || bad "files left"
[[ -f $T/etc/krb5.conf ]] && ok "a krb5.conf we did not write is kept" || bad "deleted a file that was not ours"
[[ ! -e $MONARCHY_IDENTITY_STATE && -z $(cfg login_mode) ]] && ok "not enrolled: state removed, policy cleared" || bad "state: $(cat "$MONARCHY_IDENTITY_STATE" "$MONARCHY_IDENTITY_CONF" 2>&1)"
[[ -z $(ls "$T/sss/db" "$T/sss/mc" 2>/dev/null | grep -v ":$") ]] && ok "sssd cache cleared" || bad "cache left"
[[ $(grep -c . "$T/etc/nsswitch.conf") == 4 ]] && ok "nsswitch.conf otherwise intact" || bad "nsswitch lines"
oi leave; [[ $RC -eq 0 ]] && ok "leave twice is harmless" || bad "second leave: $OUT"

echo "[SDDM autologin: our override must sort after Omarchy's autologin.conf]"
D=$T/etc/sddm.conf.d
eff() { (source "$REPO/lib/common.sh"; sddm_autologin_user); }
[[ $(eff) == tester ]] && ok "stock: Omarchy autologs in tester" || bad "stock autologin: $(eff)"
(source "$REPO/lib/common.sh"; sddm_autologin_disable); [[ -z $(eff) ]] && ok "override disables autologin" || bad "override lost to autologin.conf: $(eff)"
c1=$(cat "$D/zz-monarchy-identity.conf"); (source "$REPO/lib/common.sh"; sddm_autologin_disable); [[ $(cat "$D/zz-monarchy-identity.conf") == "$c1" ]] && ok "disable twice writes the same" || bad "not idempotent"
[[ $(ls -1 "$D" | LC_ALL=C sort | tail -1) == zz-monarchy-identity.conf ]] && ok "it sorts last (C locale)" || bad "sort order: $(ls "$D")"
(source "$REPO/lib/common.sh"; sddm_autologin_restore); [[ $(eff) == tester ]] && ok "restore gives Omarchy's autologin back" || bad "restore"
[[ -f $D/autologin.conf && -f $D/99-omarchy-login.conf ]] && ok "Omarchy's own drop-ins never touched" || bad "Omarchy files modified"
result
