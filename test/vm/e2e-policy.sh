#!/bin/bash
# Who may sign in: implied modes, all three policies, sudo groups, offline days, autologin, `policy set` without
# re-joining, refusals that change nothing, `enroll --if-needed`. Needs DC + VM.
source "$(dirname "$0")/lib.sh"
allowed() { reset_locks; [[ $(pt sddm "$1" "$PW") == ALLOWED* ]]; }
can_sudo() { "${V[@]}" "sudo sudo -l -U $1 2>&1" | grep -q "(ALL : ALL) ALL"; }
autologin() { st | grep -o '"autologin":[a-z]*' | cut -d: -f2; }
pwset() { dc computer show 'OI-CLIENT$' | sed -n 's/^pwdLastSet: //p'; }
SUDOERS=/etc/sudoers.d/50-monarchy-identity
fresh

echo "[enroll: --groups alone implies the mode; autologin off by default]"
[[ $(autologin) == true ]] && ok "before: Omarchy autologin on (fixture)" || bad "fixture autologin: $(autologin)"
out=$(enroll --groups oi-laptop-users --sudo-groups oi-admins)
[[ $out == *"enrolled in CORP.TEST"* && $out == *"login mode: groups"* ]] && ok "enrolled, mode groups" || { bad "enroll"; sed 's/^/      /' <<<"$out"; }
[[ $(autologin) == false ]] && ok "autologin turned off" || bad "autologin: $(autologin)"
P0=$(pwset)

echo "[groups + sudo]"
allowed alice && allowed bob && ok "alice and bob allowed" || bad "group members"
allowed carol && bad "carol allowed" || ok "carol (not in group) denied"
[[ $("${V[@]}" "sudo stat -c '%a %U' $SUDOERS") == "440 root" ]] && ok "sudoers drop-in 0440 root" || bad "sudoers mode"
can_sudo alice && ok "alice (oi-admins) has sudo" || bad "alice lacks sudo"
can_sudo bob && bad "bob has sudo" || ok "bob (not in oi-admins) has no sudo"
check "visudo -c clean" "${V[@]}" 'sudo visudo -c >/dev/null 2>&1'
[[ $(cli policy show) == *"login mode:    groups"* ]] && ok "policy show works without root" || bad "policy show: $(cli policy show)"

echo "[reassert restores deleted drop-ins]"
"${V[@]}" "sudo rm -f $SUDOERS /etc/sddm.conf.d/zz-monarchy-identity.conf"
scli reassert >/dev/null
can_sudo alice && [[ $(autologin) == false ]] && ok "sudo and autologin override back" || bad "reassert: sudo=$(can_sudo alice && echo y) autologin=$(autologin)"

echo "[policy set: --users alone implies assigned; no re-join]"
[[ $(scli policy set --users alice) == *"mode=assigned"* ]] && ok "policy set --users" || bad "policy set --users"
allowed alice && ok "alice allowed" || bad "alice denied"
allowed bob && bad "bob still allowed" || ok "bob denied (in group, not listed)"
can_sudo alice && ok "sudo untouched by a change that didn't mention it" || bad "sudo lost"
[[ $(pwset) == "$P0" ]] && ok "computer account not re-joined" || bad "re-joined"

echo "[policy set: any, offline days]"
scli policy set --mode any --offline-days 3 >/dev/null
allowed carol && ok "carol allowed under any" || bad "carol denied under any"
check "offline_credentials_expiration = 3 written" "${V[@]}" 'sudo grep -q "^offline_credentials_expiration = 3" /etc/sssd/sssd.conf'
check "sssctl config-check accepts the generated sssd.conf" "${V[@]}" 'sudo timeout 20 sssctl config-check </dev/null >/dev/null 2>&1'

echo "[policy set: back to groups, sudo removed]"
scli policy set --groups oi-laptop-users --sudo-groups - --offline-days 0 >/dev/null
allowed carol && bad "carol still allowed" || ok "carol denied again"
can_sudo alice && bad "alice still has sudo" || ok "--sudo-groups - removed sudo"
scli reassert >/dev/null; check "reassert doesn't bring removed sudo back" "${V[@]}" "test ! -e $SUDOERS"

echo "[refused changes change nothing]"
S0=$(cli policy show)
[[ $(scli policy set --mode groups --groups '') == *"needs --groups"* ]] && ok "no groups refused" || bad "empty groups"
[[ $(scli policy set --groups 'bad;group') == *"invalid --groups"* ]] && ok "invalid group name refused" || bad "invalid group"
[[ $(scli policy set --groups no-such-group) == *"has no group named"* ]] && ok "unknown group refused" || bad "unknown group"
[[ $(scli policy set --mode bogus) == *"bad --mode"* ]] && ok "bogus mode refused" || bad "bogus mode"
[[ $(scli policy set --offline-days abc) == *"invalid --offline-days"* ]] && ok "bad --offline-days refused" || bad "offline-days"
[[ $(cli policy set --mode any) == *"administrator rights"* ]] && ok "non-root refused" || bad "non-root allowed"
[[ $(cli policy show) == "$S0" ]] && ok "policy unchanged" || bad "policy changed"
allowed bob && ok "bob still allowed" || bad "bob locked out"

echo "[back-to-back changes don't trip systemd's start limit]"
for _ in 1 2 3; do scli policy set --mode any >/dev/null; scli policy set --groups oi-laptop-users >/dev/null; done
[[ $("${V[@]}" 'systemctl is-active sssd') == active ]] && ok "sssd active after 6 quick restarts" || bad "sssd $("${V[@]}" 'systemctl is-active sssd')"
allowed bob && ok "sign-in still works" || bad "sign-in broken"

echo "[enroll --if-needed]"
out=$(enroll --groups oi-admins --if-needed)
[[ $out == *"converging policy without re-joining"* ]] && ok "enrolled machine: converged" || bad "if-needed: $out"
allowed alice && ok "alice (oi-admins) allowed" || bad "alice"
allowed bob && bad "bob still allowed" || ok "bob (not in oi-admins) denied"
[[ $(pwset) == "$P0" ]] && ok "still not re-joined" || bad "re-joined"
out=$(echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity enroll --realm OTHER.EXAMPLE --groups g --if-needed' 2>&1)
[[ $out == *"already enrolled in"* ]] && ok "different realm refused" || bad "other realm: $out"

echo "[leave turns autologin back on; --if-needed on a fresh machine enrolls]"
leave
[[ $(autologin) == true ]] && ok "autologin back on" || bad "autologin: $(autologin)"
check "sudoers drop-in gone" "${V[@]}" "test ! -e $SUDOERS"
enroll_ok --groups oi-laptop-users --if-needed --keep-autologin
[[ $(autologin) == true ]] && ok "--keep-autologin keeps it" || bad "autologin: $(autologin)"
leave
result
