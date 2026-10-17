#!/bin/bash
# Core: enroll, sign-in through every Omarchy PAM service, password change, repair after overwrite, local users
# unaffected when sssd or pam_sss.so is gone, and leave. One enrollment for all of it. Needs DC + VM.
source "$(dirname "$0")/lib.sh"
SSS=/usr/lib/security/pam_sss.so
pt_as() { local u=$1; shift; "${V[@]}" "sudo -u $u python3 -I /tmp/pamtest.py$(q "$@")" 2>&1; }   # pam_sss refuses root-initiated password changes
trap 'dc user setpassword alice --newpassword="$PW" >/dev/null; "${V[@]}" "echo tester:tester | sudo chpasswd; test -e $SSS.off && sudo mv $SSS.off $SSS" >/dev/null 2>&1' EXIT
fresh
"${V[@]}" 'sudo rm -rf /home/alice /home/bob /home/carol'

echo "[enroll]"
enroll_ok --groups oi-laptop-users
s=$(st); [[ $s == *'"enrolled":true'* && $s == *'"login_mode":"groups"'* && $s != *'"false"'* ]] && ok "status: enrolled, groups, every check true" || bad "status: $s"

echo "[sign-in on every service]"
for svc in system-auth omarchy-lock-password sddm sudo login sshd system-remote-login; do
  sess=--session; [[ $svc == omarchy-lock-password ]] && sess=""   # unlocking authenticates; it opens no session
  expect ALLOWED "$svc: alice (in group)" $sess "$svc" alice "$PW"
  expect DENIED  "$svc: carol (not in group)" "$svc" carol "$PW"
  expect DENIED  "$svc: bob, wrong password" "$svc" bob wrong
  expect ALLOWED "$svc: tester (local)" "$svc" tester tester
done
check "alice's home created on first sign-in, mode 700" test "$("${V[@]}" 'sudo stat -c "%U %a" /home/alice' 2>&1)" == "alice 700"
check "carol (refused) got no home" "${V[@]}" 'test ! -e /home/carol'

echo "[passwords]"
reset_locks
[[ $(pt_as alice passwd alice "$PW" --chauthtok 'N3w-Passw0rd!') == PASSWORD-CHANGED* ]] && ok "alice changes her directory password with passwd" || bad "alice passwd"
expect ALLOWED "alice: new password works" system-auth alice 'N3w-Passw0rd!'
expect DENIED  "alice: old password refused" system-auth alice "$PW"
dc user setpassword alice --newpassword="$PW" >/dev/null; reset_locks
expect PASSWORD-CHANGED "tester: local passwd still changes the local password" passwd tester tester --chauthtok 'tester2-pw'
"${V[@]}" 'echo tester:tester | sudo chpasswd'

echo "[repair after something overwrites the sign-in config]"
"${V[@]}" 'sudo python3 -I ~/oi/lib/pamedit.py remove /etc/pam.d/system-auth; sudo sed -i -E "/^(passwd|group|shadow):/ s/[[:space:]]+sss\b//" /etc/nsswitch.conf'
s=$(st); [[ $s == *'"pam_system_auth":"false"'* && $s == *'"nss_sss":"false"'* ]] && ok "status shows the overwrite" || bad "status: $s"
scli reassert >/dev/null
s=$(st); [[ $s == *'"pam_system_auth":"true"'* && $s == *'"nss_sss":"true"'* ]] && ok "reassert puts it back" || bad "after reassert: $s"
expect ALLOWED "alice signs in again" system-auth alice "$PW"

echo "[local users don't depend on the directory]"
"${V[@]}" 'sudo systemctl stop $(systemctl list-units --all --no-legend --plain "sssd*" | cut -d" " -f1)' >/dev/null 2>&1   # sockets too, or they restart it
for svc in sudo sddm sshd; do expect ALLOWED "sssd stopped: $svc tester (local)" "$svc" tester tester; done
expect DENIED "sssd stopped: alice gets a prompt answer" system-auth alice "$PW"
# if a check below bricks every login, this root timer (no PAM involved) restores the module
"${V[@]}" "sudo systemd-run --quiet --unit=oi-restore-pam --on-active=120s /bin/sh -c 'test -e $SSS.off && mv $SSS.off $SSS'"
"${V[@]}" "sudo mv $SSS $SSS.off"
for svc in sudo sddm sshd; do expect ALLOWED "pam_sss.so missing: $svc tester (local)" "$svc" tester tester; done
expect DENIED "pam_sss.so missing: alice refused, not waved through" system-auth alice "$PW"
"${V[@]}" "sudo mv $SSS.off $SSS; sudo systemctl stop oi-restore-pam.timer; sudo systemctl start sssd"
scli reassert >/dev/null; reset_locks
expect ALLOWED "alice works again once sssd is back" system-auth alice "$PW"

echo "[leave]"
leave
check "PAM back to stock" pam_stock
check "nsswitch has no sss" "${V[@]}" '! grep -qE "^(passwd|group|shadow):.*sss" /etc/nsswitch.conf'
check "sssd, krb5 and samba config removed" "${V[@]}" 'sudo test ! -e /etc/sssd/sssd.conf -a ! -e /etc/krb5.conf -a ! -e /etc/samba/smb.conf -a ! -e /etc/krb5.keytab'
check "computer account deleted" bash -c '! docker exec oi-test-dc samba-tool computer list | grep -qxF "OI-CLIENT\$"'
[[ $(st) == *'"enrolled":false'* ]] && ok "status: not enrolled" || bad "status after leave: $(st)"
expect ALLOWED "tester (local) fine after leave" system-auth tester tester
result
