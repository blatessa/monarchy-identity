#!/bin/bash
# The directory's answers over time: an expired password must be changed first; cached sign-in works with the DC
# down (but not for people never seen here), and everything recovers when it returns. Needs DC + VM.
source "$(dirname "$0")/lib.sh"
NEW='D4ve-New-Pw!'
clock() { "${V[@]}" "sudo timedatectl set-ntp false; sudo date -s @\$((\$(date +%s) + $1)) >/dev/null"; }   # clock SECONDS: move the VM's clock
DAY=86400 SHIFT=0
trap 'clock $((-SHIFT)) 2>/dev/null; "${V[@]}" "sudo timedatectl set-ntp true" 2>/dev/null; docker start oi-test-dc >/dev/null 2>&1; for u in dave erin; do dc user delete $u >/dev/null; done; dc domain passwordsettings set --account-lockout-threshold=0 >/dev/null' EXIT
fresh
for u in dave erin; do dc user delete $u >/dev/null; dc user create $u "$PW" --must-change-at-next-login >/dev/null; done
dc group addmembers oi-laptop-users dave >/dev/null
dc domain passwordsettings set --account-lockout-threshold=50 >/dev/null   # the DC only counts bad passwords with a threshold
enroll_ok --groups oi-laptop-users
MARK=/run/monarchy-identity/password-change
marked() { "${V[@]}" "sudo test -e $MARK/$1"; }
bad_pw() { docker exec oi-test-dc ldbsearch -H /var/lib/samba/private/sam.ldb "(sAMAccountName=$1)" badPwdCount 2>/dev/null | awk '/^badPwdCount:/ {print $2}'; }

echo "[expired password at the login screen: let through, to change it first]"
expect ALLOWED "sddm: dave (expired, allowed group) gets past the login screen" sddm dave "$PW"
marked dave && ok "  ... marked, so the session shows the change-password screen first" || bad "dave not marked"
reset_locks; before=$(bad_pw dave)
expect DENIED "sddm: dave with a wrong password is refused" sddm dave wrong-password
[[ $(bad_pw dave) == $((before + 1)) ]] && ok "  ... counted once by the directory (the re-check never sees a wrong password)" || bad "bad password count went from $before to $(bad_pw dave)"
expect DENIED "sddm: erin (expired, not in an allowed group) is refused" sddm erin "$PW"
! marked erin && ok "  ... and not marked" || bad "erin marked"
expect ALLOWED "sddm: alice (current password) signs in as before" sddm alice "$PW"
! marked alice && ok "  ... not marked" || bad "alice marked"
expect DENIED "sddm: carol (not allowed) is refused as before" sddm carol "$PW"
expect ALLOWED "sddm: tester (local) signs in as before" sddm tester tester
"${V[@]}" 'sudo touch -d "+1 hour" /etc/sddm.conf.d/zz-monarchy-identity-session.conf'
expect DENIED "sddm older than the session command (not restarted since enroll): dave refused, no desktop without the change" sddm dave "$PW"
"${V[@]}" 'sudo touch -d "-1 hour" /etc/sddm.conf.d/zz-monarchy-identity-session.conf'
out=$(pt sshd dave "$PW"); [[ $out == DENIED*"new one required"* ]] && ok "sshd: still refused, new password required" || bad "sshd: $out"
reset_locks
[[ $("${V[@]}" "sudo -u dave python3 -I /tmp/pamtest.py$(q passwd dave "$PW" --chauthtok "$NEW")" 2>&1) == PASSWORD-CHANGED* ]] && ok "dave changes it with passwd" || bad "dave passwd"
expect ALLOWED "dave signs in with the new password" --session sddm dave "$NEW"
! marked dave && ok "  ... and is no longer marked (each sign-in that passes the password check decides afresh)" || bad "dave still marked"

echo "[domain controller down]"
expect ALLOWED "alice signs in once while online (fills the cache)" system-auth alice "$PW"
docker stop oi-test-dc >/dev/null; sleep 3
[[ $(enroll --groups oi-laptop-users) == *"no domain controller answered at dc.corp.test"* ]] && ok "enroll refused while the DC is down (before changing anything)" || bad "DC down: enroll not refused"
expect ALLOWED "alice (cached) signs in offline" system-auth alice "$PW"
expect DENIED  "alice, wrong password, refused offline" system-auth alice wrong
expect DENIED  "bob (never signed in here) refused offline" system-auth bob "$PW"
expect ALLOWED "tester (local) fine offline" system-auth tester tester

echo "[offline sign-in expiry (--offline-days)]"
clock $((3*DAY)); SHIFT=$((3*DAY))
expect ALLOWED "no expiry set: alice still signs in 3 days after her last online sign-in" system-auth alice "$PW"
clock $((-3*DAY)); SHIFT=0
scli policy set --offline-days 2 >/dev/null; reset_locks
expect ALLOWED "--offline-days 2, set while offline: alice signs in the same day" system-auth alice "$PW"
clock $((3*DAY)); SHIFT=$((3*DAY))
expect DENIED  "--offline-days 2: alice refused 3 days after her last online sign-in" system-auth alice "$PW"
expect ALLOWED "  ... tester (local) unaffected" system-auth tester tester
clock $((-3*DAY)); SHIFT=0; reset_locks
scli policy set --offline-days 0 >/dev/null; reset_locks
"${V[@]}" 'sudo timedatectl set-ntp true'

echo "[domain controller back]"
docker start oi-test-dc >/dev/null
timeout 120 bash -c 'until docker exec oi-test-dc samba-tool domain level show >/dev/null 2>&1; do sleep 2; done'
"${V[@]}" 'sudo systemctl kill -s SIGUSR2 sssd' 2>/dev/null   # ask sssd to go online now instead of at its next retry
for _ in $(seq 20); do out=$(pt system-auth bob "$PW"); [[ $out == ALLOWED* ]] && break; sleep 3; done
[[ $out == ALLOWED* ]] && ok "bob signs in once the DC is back" || bad "after recovery: $out"
leave
result
