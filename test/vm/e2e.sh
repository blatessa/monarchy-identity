#!/bin/bash
# Core: what only real sssd, PAM and a real directory can show. Sign-in through every Omarchy PAM service, admin
# prompts, password change, repair after overwrite, who-may-sign-in policies and sudo, local users unaffected when sssd or pam_sss.so is
# gone, `leave`; then the directory's refusals and enrollment options against the real DC. The logic around these
# (validation, generated config, PAM edits, status) is in test/unit. Needs DC + VM.
source "$(dirname "$0")/lib.sh"
SSS=/usr/lib/security/pam_sss.so
pt_as() { local u=$1; shift; "${V[@]}" "sudo -u $u python3 -I /tmp/pamtest.py$(q "$@")" 2>&1; }   # pam_sss refuses root-initiated password changes
can_sudo() { "${V[@]}" "sudo sudo -l -U $1 2>&1" | grep -q "(ALL : ALL) ALL"; }
allowed() { reset_locks; [[ $(pt sddm "$1" "$PW") == ALLOWED* ]]; }
trap 'dc user setpassword alice --newpassword="$PW" >/dev/null; dc ou delete "OU=Laptops,DC=corp,DC=test" >/dev/null; for c in "OI-CLIENT\$" "LAPTOP-0042\$"; do dc computer delete "$c" >/dev/null; done
  "${V[@]}" "echo tester:tester | sudo chpasswd; test -e $SSS.off && sudo mv $SSS.off $SSS; sudo rm -f /root/oi.pw" >/dev/null 2>&1' EXIT
fresh
"${V[@]}" 'sudo rm -rf /home/alice /home/bob /home/carol'

echo "[the directory says no: nothing changes]"
out=$(echo wrong | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll$(q $LAB --groups oi-laptop-users)" 2>&1)
[[ $out == *"could not search the directory"* ]] && ok "wrong password refused" || bad "wrong password: $out"
[[ $(enroll --groups oi-laptop-users,no-such-group) == *"has no group named: no-such-group"* ]] && ok "unknown group refused" || bad "unknown group"
check "PAM still stock after both refusals" pam_stock

echo "[enroll]"
enroll_ok --groups oi-laptop-users --sudo-groups oi-admins
s=$(st); [[ $s == *'"enrolled":true'* && $s == *'"login_mode":"groups"'* && $s != *'"false"'* ]] && ok "status: enrolled, groups, every check true" || bad "status: $s"

echo "[sign-in on every service]"
for svc in system-auth omarchy-lock-password sddm sudo login sshd system-remote-login polkit-1; do
  sess=--session; [[ $svc == omarchy-lock-password || $svc == polkit-1 ]] && sess=""   # these authenticate; they open no session
  expect ALLOWED "$svc: alice (in group)" $sess "$svc" alice "$PW"
  expect DENIED  "$svc: carol (not in group)" "$svc" carol "$PW"
  expect DENIED  "$svc: bob, wrong password" "$svc" bob wrong
  expect ALLOWED "$svc: tester (local)" "$svc" tester tester
done
check "alice's home created on first sign-in, mode 700" test "$("${V[@]}" 'sudo stat -c "%U %a" /home/alice' 2>&1)" == "alice 700"
check "carol (refused) got no home" "${V[@]}" 'test ! -e /home/carol'

echo "[admin prompts: a real polkit prompt, through its sandboxed helper]"
check "polkit's agent helper is socket-activated, as on Omarchy" "${V[@]}" 'systemctl is-active -q polkit-agent-helper.socket'
reset_locks
# WANT|DESC|ASKER|IDENTITY|PASSWORD. Identity "-" answers as the first offered, as Omarchy's dialog does (no choice shown)
for a in "AUTHORIZED|alice (oi-admins) answers with her directory password|tester|alice|$PW" "REFUSED|alice, wrong password|tester|alice|wrong" \
         "NOT-OFFERED|bob (not in oi-admins) is not offered as an admin|tester|bob|$PW" "AUTHORIZED|tester (local admin) still answers|tester|tester|tester" \
         "AUTHORIZED alice|alice asking: the prompt asks for her own password|alice|-|$PW" \
         "AUTHORIZED tester|bob asking: the prompt asks for an admin's password|bob|-|tester"; do
  IFS='|' read -r want desc asker who pw <<<"$a"; out=$("${V[@]}" "sudo -u $asker python3 -I /tmp/adminprompt.py$(q "$who" "$pw")" 2>&1)
  [[ $out == "$want"* ]] && ok "$desc" || bad "$desc (got: ${out:-<nothing>})"
done

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

echo "[who may sign in, as sssd enforces it]"
can_sudo alice && ok "alice (oi-admins) has sudo" || bad "alice lacks sudo"
can_sudo bob && bad "bob has sudo" || ok "bob (not in oi-admins) has no sudo"
check "visudo accepts the drop-in" "${V[@]}" 'sudo visudo -c >/dev/null 2>&1'
scli policy set --users alice >/dev/null
allowed alice && ok "assigned: alice allowed" || bad "assigned: alice denied"
allowed bob && bad "assigned: bob (in the group, not listed) allowed" || ok "assigned: bob denied"
scli policy set --mode any --offline-days 3 >/dev/null
allowed carol && ok "any: carol allowed" || bad "any: carol denied"
check "sssctl config-check accepts the generated sssd.conf" "${V[@]}" 'sudo timeout 20 sssctl config-check </dev/null >/dev/null 2>&1'
scli policy set --groups oi-laptop-users --sudo-groups - --offline-days 0 >/dev/null
allowed carol && bad "groups again: carol allowed" || ok "groups again: carol denied"
can_sudo alice && bad "alice kept sudo" || ok "--sudo-groups - removed sudo"
[[ $(admin_prompt alice "$PW") == NOT-OFFERED* ]] && ok "... and alice is no longer offered at admin prompts" || bad "alice still an admin at prompts"
for _ in 1 2 3; do scli policy set --mode any >/dev/null; scli policy set --groups oi-laptop-users >/dev/null; done
[[ $("${V[@]}" 'systemctl is-active sssd') == active ]] && allowed bob && ok "6 quick restarts: sssd active, sign-in works" || bad "systemd start limit tripped"

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

echo "[enroll options against the real directory: --computer-name, --ou, --password-file]"
"${V[@]}" "sudo install -m 600 /dev/null /root/oi.pw && echo '$PW' | sudo tee /root/oi.pw >/dev/null"
dc ou create "OU=Laptops,DC=corp,DC=test" >/dev/null
out=$("${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll$(q $LAB --groups oi-laptop-users --computer-name LAPTOP-0042 --ou OU=Laptops,DC=corp,DC=test --password-file /root/oi.pw) </dev/null" 2>&1); reset_locks
[[ $out == *"enrolled in CORP.TEST as LAPTOP-0042"* ]] && ok "enrolled as LAPTOP-0042" || { bad "enroll"; sed 's/^/      /' <<<"$out"; }
dn=$(dc computer show 'LAPTOP-0042$' | sed -n 's/^dn: //p')
[[ $dn == "CN=LAPTOP-0042,OU=Laptops,DC=corp,DC=test" ]] && ok "account created in the OU" || bad "DN: $dn"
has_account 'OI-CLIENT$' && bad "an account named after the hostname was also created" || ok "no account named after the hostname"
expect ALLOWED "alice signs in as LAPTOP-0042" sddm alice "$PW"
"${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator --password-file /root/oi.pw </dev/null' >/dev/null 2>&1
has_account 'LAPTOP-0042$' && bad "account left behind" || ok "leave --password-file deleted the account"

echo "[an account that exists already: refused for another laptop, taken over with --replace-computer-account]"
dc computer create OI-CLIENT >/dev/null
before=$(dc computer show 'OI-CLIENT$' | grep -E '^(pwdLastSet|whenChanged)')
[[ $(enroll --groups oi-laptop-users) == *"DIFFERENT laptop"* ]] && ok "refused" || bad "existing account not refused"
[[ $(dc computer show 'OI-CLIENT$' | grep -E '^(pwdLastSet|whenChanged)') == "$before" ]] && ok "that account was left alone" || bad "existing account modified"
out=$("${V[@]}" "sudo OI_ADMIN_PASSWORD_FILE=/root/oi.pw ~/oi/bin/monarchy-identity enroll$(q $LAB --groups oi-laptop-users --replace-computer-account) </dev/null" 2>&1); reset_locks
[[ $out == *"enrolled in"* ]] && ok "took over the existing account" || { bad "replace"; sed 's/^/      /' <<<"$out"; }
echo "[an enrollment that stopped before sign-in was switched on can simply be re-run]"
"${V[@]}" 'sudo python3 -I ~/oi/lib/pamedit.py remove /etc/pam.d/system-auth; printf "provider = \"local\"\n" | sudo tee /etc/monarchy-identity/config.toml >/dev/null'
out=$(enroll --groups oi-laptop-users)
[[ $out == *"reusing existing computer account"* && $out == *"enrolled in"* ]] && ok "re-run reuses this laptop's own account, no flag needed" || { bad "re-run"; sed 's/^/      /' <<<"$out"; }
expect ALLOWED "alice signs in" system-auth alice "$PW"
leave
result
