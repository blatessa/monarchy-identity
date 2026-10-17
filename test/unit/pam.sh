#!/bin/bash
# The edits to PAM, nsswitch and SDDM, on Omarchy's real files: apply, remove, idempotent, skip counts, only marked
# files removed on `leave`, autologin merge order. Whether the stack then authenticates is the lab's job.
source "$(dirname "$0")/lib.sh"
sandbox
PE=(python3 -I "$REPO/lib/pamedit.py")
SA=$T/etc/pam.d/system-auth LP=$T/etc/pam.d/omarchy-lock-password
rule() { grep -F -- "$2" "$1" | head -1 | tr -s ' '; }

echo "[pamedit on Omarchy's files]"
for f in system-auth omarchy-lock-password; do
  stock=$(cat "$T/etc/pam.d/$f"); "${PE[@]}" apply "$T/etc/pam.d/$f"; once=$(cat "$T/etc/pam.d/$f")
  [[ $once != "$stock" ]] && ok "$f: apply changes it" || bad "$f: apply did nothing"
  "${PE[@]}" apply "$T/etc/pam.d/$f"; [[ $(cat "$T/etc/pam.d/$f") == "$once" ]] && ok "$f: apply twice is the same as once" || bad "$f: not idempotent"
  "${PE[@]}" check "$T/etc/pam.d/$f" && ok "$f: check sees the edit" || bad "$f: check"
  "${PE[@]}" remove "$T/etc/pam.d/$f"; [[ $(cat "$T/etc/pam.d/$f") == "$stock" ]] && ok "$f: remove restores the file byte for byte" || bad "$f: remove"
  ! "${PE[@]}" check "$T/etc/pam.d/$f" && ok "$f: check is false after remove" || bad "$f: check after remove"
done
"${PE[@]}" apply "$SA"
[[ $(rule "$SA" 'pam_sss.so forward_pass') == "-auth [success=3 default=ignore] pam_sss.so forward_pass" ]] && ok "auth skips systemd_home, unix and faillock authfail (success=3)" || bad "auth skip: $(rule "$SA" forward_pass)"
[[ $(rule "$SA" 'module_unknown=ignore') == "-account [success=2 user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad] pam_sss.so" ]] && ok "account: unknown/unavailable ignored, skips systemd_home and unix" || bad "account rule"
grep -qE '^-password +\[success=2 default=ignore\] +pam_sss.so' "$SA" && ok "password skip count" || bad "password rule"
grep -qx 'session    required   pam_mkhomedir.so umask=0077' "$SA" && ok "pam_mkhomedir at the top of session" || bad "mkhomedir"
! grep -E '^[^#]*pam_sss' "$SA" | grep -vq '^-' && ok "every pam_sss rule is -prefixed (safe when the module is missing)" || bad "a pam_sss rule is not -prefixed"
[[ $(grep -c 'BEGIN monarchy-identity' "$SA") == 4 ]] && ok "four marked blocks" || bad "blocks: $(grep -c BEGIN "$SA")"
"${PE[@]}" remove "$SA"
echo "[a plain stack (no systemd_home, no faillock) still gets a correct skip count]"
printf '#%%PAM-1.0\nauth required pam_unix.so\naccount required pam_unix.so\nsession required pam_unix.so\n' > "$T/plain"
"${PE[@]}" apply "$T/plain"; grep -qF -- '-auth      [success=1 default=ignore]  pam_sss.so forward_pass' "$T/plain" && ok "plain stack: success=1" || bad "plain: $(cat "$T/plain")"
echo "[a file with no pam_unix at all is left alone]"
printf '#%%PAM-1.0\nauth required pam_deny.so\n' > "$T/odd"; cp "$T/odd" "$T/odd.0"; "${PE[@]}" apply "$T/odd"; cmp -s "$T/odd" "$T/odd.0" && ok "unchanged" || bad "odd file modified"
echo "[permissions survive an edit]"
chmod 0640 "$SA"; "${PE[@]}" apply "$SA"; [[ $(stat -c %a "$SA") == 640 ]] && ok "mode kept" || bad "mode changed"; "${PE[@]}" remove "$SA"

echo "[enroll and leave]"
enroll --groups oi-laptop-users; [[ $OUT == *"enrolled in"* ]] || { bad "enroll: $OUT"; }
has_pam system-auth && has_pam omarchy-lock-password && ok "both Omarchy services edited" || bad "PAM not applied"
for f in login sudo sddm su; do ! has_pam "$f" && continue; bad "$f was edited"; done; ok "other services (sudo, login, sddm, su) untouched; they include system-auth"
grep -qE '^passwd:.*files sss systemd' "$T/etc/nsswitch.conf" && grep -qE '^group:.*files sss ' "$T/etc/nsswitch.conf" && grep -qE '^shadow:.*files sss' "$T/etc/nsswitch.conf" && ok "nsswitch: sss after files for passwd, group, shadow" || bad "nsswitch: $(cat "$T/etc/nsswitch.conf")"
grep -q '^hosts: files dns$' "$T/etc/nsswitch.conf" && ok "hosts line untouched" || bad "hosts changed"
oi reassert; [[ $(grep -c sss "$T/etc/nsswitch.conf") == 3 && $(grep -c 'BEGIN monarchy' "$SA") == 4 ]] && ok "reassert is idempotent" || bad "reassert duplicated edits"
echo "[reassert repairs what an update overwrote]"
cp "$FIX/pam.d/system-auth" "$SA"; sed -i -E '/^(passwd|group|shadow):/ s/[[:space:]]+sss\b//' "$T/etc/nsswitch.conf"
oi reassert; has_pam system-auth && grep -qE '^passwd:.*sss' "$T/etc/nsswitch.conf" && ok "PAM and nsswitch back" || bad "reassert: $OUT"
echo "[leave removes only what is marked]"
touch "$T/sss/db/cache.ldb" "$T/sss/mc/passwd"
printf '[libdefaults]\n' > "$T/etc/krb5.conf"          # someone replaced our krb5.conf with their own: not ours to delete
oi leave
for f in system-auth omarchy-lock-password; do cmp -s "$FIX/pam.d/$f" "$T/etc/pam.d/$f" && ok "$f back to stock" || bad "$f differs from stock"; done
grep -qE '^(passwd|group|shadow):.*sss' "$T/etc/nsswitch.conf" && bad "sss still in nsswitch" || ok "nsswitch has no sss"
[[ ! -e $T/etc/sssd/sssd.conf && ! -e $T/etc/samba/smb.conf && ! -e $T/etc/krb5.keytab ]] && ok "sssd.conf, smb.conf and the keytab removed" || bad "files left"
[[ -f $T/etc/krb5.conf ]] && ok "a krb5.conf we did not write is kept" || bad "deleted a file that was not ours"
[[ $(cfg provider) == local ]] && ok "state: local" || bad "state: $(cat "$MONARCHY_IDENTITY_CONF")"
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
