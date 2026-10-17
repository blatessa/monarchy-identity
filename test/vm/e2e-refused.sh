#!/bin/bash
# Everything enroll must refuse before sign-in changes: no policy, bad input, wrong password, unknown group, DC down,
# colliding or generic computer names, unsafe password files. Nothing is ever enrolled here. Needs DC + VM.
source "$(dirname "$0")/lib.sh"
trap 'docker start oi-test-dc >/dev/null 2>&1; "${V[@]}" "sudo sysctl -qw kernel.hostname=oi-client; sudo rm -f /root/oi.pw /tmp/oi-open.pw" >/dev/null 2>&1; dc computer delete "OI-CLIENT\$" >/dev/null' EXIT
fresh

# Everything that could make a laptop sign in differently; compared after every refusal.
snap() { "${V[@]}" 'sudo bash -c "cat /etc/pam.d/system-auth /etc/pam.d/omarchy-lock-password /etc/nsswitch.conf; ls /etc/sddm.conf.d /etc/sudoers.d
  test -e /etc/sssd/sssd.conf && echo sssd.conf; test -e /etc/krb5.keytab && echo keytab; systemctl is-active sssd; cat /etc/monarchy-identity/config.toml"' 2>&1; }
BEFORE=$(snap)
refused() { # refused <label> <expected message> <enroll output>
  [[ $3 == *"$2"* ]] && ok "$1: refused ('$2')" || { bad "$1: expected '$2'"; tail -3 <<<"$3" | sed 's/^/      /'; }
  [[ $(snap) == "$BEFORE" ]] || { bad "$1: machine changed"; diff <(echo "$BEFORE") <(snap) | head -8 | sed 's/^/      /'; }
}
G=(--groups oi-laptop-users)

echo "[input]"
refused "no policy"         "say who may sign in" "$(enroll)"
refused "groups mode, no groups" "needs --groups" "$(enroll --mode groups)"
refused "bogus mode"        "bad --mode"          "$(enroll "${G[@]}" --mode bogus)"
refused "realm injection"   "invalid --realm"     "$(enroll "${G[@]}" --realm $'corp.test\n[evil]')"
refused "group injection"   "invalid --groups"    "$(enroll --groups $'a\nsimple_allow_users = evil')"
refused "sudo-groups"       "invalid --sudo-groups" "$(enroll "${G[@]}" --sudo-groups 'x$(id)')"
refused "offline-days"      "invalid --offline-days" "$(enroll "${G[@]}" --offline-days abc)"
refused "ou"                "invalid --ou"        "$(enroll "${G[@]}" --ou 'OU=x;rm -rf /,DC=corp,DC=test')"
refused "computer-name"     "invalid --computer-name" "$(enroll "${G[@]}" --computer-name TOO-LONG-COMPUTER-NAME)"
out=$("${V[@]}" '~/oi/bin/monarchy-identity enroll --help' 2>&1); [[ $out == *"--groups a,b"* ]] && ok "enroll --help works without root" || bad "help: $out"

echo "[the directory says no]"
refused "wrong password" "could not search the directory" "$(echo wrong | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll$(q $LAB "${G[@]}")" 2>&1)"
refused "unknown group"  "has no group named: no-such-group" "$(enroll --groups oi-laptop-users,no-such-group)"
docker stop oi-test-dc >/dev/null
refused "DC down" "could not search the directory" "$(enroll "${G[@]}")"
docker start oi-test-dc >/dev/null; timeout 120 bash -c 'until docker exec oi-test-dc samba-tool domain level show >/dev/null 2>&1; do sleep 2; done'

echo "[computer names]"
dc computer create OI-CLIENT >/dev/null
before=$(dc computer show 'OI-CLIENT$' | grep -E '^(pwdLastSet|whenChanged)')
refused "another laptop's account" "DIFFERENT laptop" "$(enroll "${G[@]}")"
[[ $(dc computer show 'OI-CLIENT$' | grep -E '^(pwdLastSet|whenChanged)') == "$before" ]] && ok "that account was left alone" || bad "existing account modified"
dc computer delete 'OI-CLIENT$' >/dev/null
for hn in omarchy archlinux; do
  "${V[@]}" "sudo sysctl -qw kernel.hostname=$hn"; refused "hostname $hn" "generic '$hn'" "$(enroll "${G[@]}")"
done
"${V[@]}" 'sudo sysctl -qw kernel.hostname=a-very-long-laptop-hostname-42'
refused "long hostname" "longer than 15 characters" "$(enroll "${G[@]}")"
"${V[@]}" 'sudo sysctl -qw kernel.hostname=oi-client'

echo "[password sources]"
"${V[@]}" "sudo install -m 644 /dev/null /tmp/oi-open.pw && echo '$PW' | sudo tee /tmp/oi-open.pw >/dev/null"
refused "world-readable password file" "accessible by group/other" "$("${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll$(q $LAB "${G[@]}" --password-file /tmp/oi-open.pw) </dev/null" 2>&1)"
refused "no password at all" "password must be given" "$("${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll$(q $LAB "${G[@]}") </dev/null" 2>&1)"
result
