#!/bin/bash
# `policy set` / `policy show` / `enroll --if-needed`: change who may sign in WITHOUT re-joining. Needs DC + VM.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
A="--realm CORP.TEST --server dc.corp.test --admin Administrator"
q() { local o="" a; for a in "$@"; do o+=" $(printf '%q' "$a")"; done; printf '%s' "$o"; }   # safe remote quoting
M() { "${V[@]}" "sudo ~/oi/bin/monarchy-identity$(q "$@") 2>&1"; }
pt() { "${V[@]}" "sudo python3 -I /tmp/pamtest.py $* 2>&1"; }
allowed() { [[ $(pt sddm "$1" "$PW") == ALLOWED* ]]; }
can_sudo() { "${V[@]}" "sudo sudo -l -U $1 2>&1" | grep -q "(ALL : ALL) ALL"; }
pwset() { docker exec oi-test-dc samba-tool computer show 'OI-CLIENT$' 2>/dev/null | sed -n 's/^pwdLastSet: //p'; }
reset_locks() { "${V[@]}" 'for u in alice bob carol; do sudo faillock --user $u --reset 2>/dev/null; done'; }
shown() { M policy show; }

scp -q -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P 2222 pamtest.py tester@127.0.0.1:/home/tester/
./deploy.sh --fixtures >/dev/null; "${V[@]}" 'sudo install -m 644 ~/pamtest.py /tmp/pamtest.py'
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $A --mode groups --groups oi-laptop-users --sudo-groups oi-admins" 2>&1)
[[ $out == *"enrolled in"* ]] && ok "enroll (groups: oi-laptop-users, sudo: oi-admins)" || { bad enroll; echo "$out" | sed 's/^/      /'; }
reset_locks; P0=$(pwset); [[ -n $P0 ]] || bad "could not read the computer account's pwdLastSet"

echo "[baseline]"
allowed alice && allowed bob && ok "alice and bob allowed" || bad "baseline allow"
allowed carol && bad "carol allowed at baseline" || ok "carol denied"
can_sudo alice && ok "alice has sudo" || bad "alice lacks sudo"
[[ $(shown) == *"login mode:    groups"* && $(shown) == *"oi-laptop-users"* ]] && ok "policy show reflects it" || bad "policy show: $(shown)"
[[ $("${V[@]}" '~/oi/bin/monarchy-identity policy show >/dev/null 2>&1; echo $?') == 0 ]] && ok "policy show needs no root" || bad "policy show as user"

echo "[policy set: groups -> assigned (alice only), no re-join]"
out=$(M policy set --mode assigned --users alice); [[ $out == *"policy updated"* ]] && ok "policy set --mode assigned" || { bad "set assigned"; echo "$out" | sed 's/^/      /'; }
reset_locks
allowed alice && ok "alice allowed" || bad "alice denied after assigned"
allowed bob && bad "bob still allowed (not assigned)" || ok "bob now denied (in the group, but not assigned)"
can_sudo alice && ok "sudo untouched by a policy change that didn't mention it" || bad "sudo lost"
[[ $(pwset) == "$P0" ]] && ok "computer account NOT re-joined (pwdLastSet unchanged)" || bad "account was re-joined"
"${V[@]}" 'sudo net ads testjoin' 2>&1 | grep -q 'Join is OK' && ok "domain join still healthy" || bad "join broken"

echo "[policy set: assigned -> any]"
M policy set --mode any >/dev/null; reset_locks
allowed carol && ok "carol (no group, not assigned) allowed under any" || bad "carol denied under any"

echo "[policy set: back to groups, and remove sudo]"
M policy set --mode groups --groups oi-laptop-users --sudo-groups - >/dev/null; reset_locks
allowed bob && ok "bob allowed again" || bad "bob denied"
allowed carol && bad "carol still allowed" || ok "carol denied again"
can_sudo alice && bad "alice still has sudo after --sudo-groups -" || ok "--sudo-groups - removed sudo"
"${V[@]}" 'test ! -e /etc/sudoers.d/50-monarchy-identity' && ok "sudoers drop-in removed" || bad "sudoers file remains"
M reassert >/dev/null; "${V[@]}" 'test ! -e /etc/sudoers.d/50-monarchy-identity' && ok "reassert does not resurrect removed sudo" || bad "reassert re-added sudo"

echo "[bad changes are refused and change nothing]"
S0=$(shown)
out=$(M policy set --mode groups --groups ''); [[ $out == *"needs --groups"* ]] && ok "mode groups with no groups refused (default deny)" || bad "empty groups: $out"
out=$(M policy set --groups 'bad;group'); [[ $out == *"invalid --groups"* ]] && ok "invalid group name refused" || bad "invalid groups: $out"
out=$(M policy set --mode bogus); [[ $out == *"bad --mode"* ]] && ok "invalid mode refused" || bad "bogus mode: $out"
out=$(M policy set --offline-days abc); [[ $out == *"invalid --offline-days"* ]] && ok "invalid --offline-days refused" || bad "offline-days: $out"
[[ $(shown) == "$S0" ]] && ok "policy unchanged after the refusals" || bad "policy changed by a refused request"
out=$(M policy set --groups no-such-group-anywhere); [[ $out == *"previous policy restored"* ]] && ok "unresolvable group: previous policy restored" || bad "unresolvable: $out"
reset_locks; allowed bob && ok "bob still allowed (old policy is live again)" || bad "bob locked out after failed change"
[[ $("${V[@]}" '~/oi/bin/monarchy-identity policy set --mode any >/dev/null 2>&1; echo $?') != 0 ]] && ok "policy set refuses non-root" || bad "policy set allowed for non-root"

echo "[rapid-fire changes must not trip systemd's start limit and leave sssd failed]"
for i in 1 2 3 4 5 6 7 8; do M policy set --mode any >/dev/null; M policy set --mode groups --groups oi-laptop-users >/dev/null; done
[[ $("${V[@]}" 'systemctl is-active sssd') == active ]] && ok "sssd still active after 16 back-to-back policy changes" || bad "sssd is $("${V[@]}" 'systemctl is-active sssd') after rapid changes"
reset_locks; allowed bob && ok "directory login still works afterwards" || bad "login broken after rapid changes"
for i in 1 2 3 4 5 6; do M reassert >/dev/null; done
[[ $("${V[@]}" 'systemctl is-active sssd') == active ]] && ok "sssd active after 6 back-to-back reasserts" || bad "reassert storm broke sssd"
echo "[enroll --if-needed converges instead of re-joining]"
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $A --mode groups --groups oi-admins --if-needed" 2>&1)
[[ $out == *"converging policy without re-joining"* ]] && ok "already enrolled: converged, exit message" || { bad "if-needed: $out"; }
reset_locks
allowed alice && ok "alice (in oi-admins) allowed" || bad "alice"
allowed bob && bad "bob still allowed after converging to oi-admins" || ok "bob denied (not in oi-admins)"
[[ $(pwset) == "$P0" ]] && ok "still not re-joined" || bad "if-needed re-joined"
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd --realm OTHER.EXAMPLE --admin x --groups g --if-needed" 2>&1)
[[ $out == *"already enrolled in"* ]] && ok "different realm refused: leave first" || bad "other realm: $out"
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $A --mode groups --groups oi-laptop-users --if-needed" 2>&1)
[[ $out == *"enrolled in"* ]] && ok "--if-needed on a NOT-enrolled machine enrolls normally" || bad "if-needed fresh: $out"
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
