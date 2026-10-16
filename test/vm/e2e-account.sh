#!/bin/bash
# Directory-account safety for fleets: never take over an existing computer account, refuse generic / too-long
# hostnames, support --computer-name and --ou. Needs DC + VM.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
A="--realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users"
dc() { docker exec oi-test-dc samba-tool "$@" 2>&1; }
# every argument is %q-quoted: hostile test inputs (;, newlines) must reach the tool as DATA, never run as shell
enrol() { local q="" a; for a in "$@"; do q+=" $(printf '%q' "$a")"; done
  echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd $A$q" 2>&1; }
leave() { echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1; }
st() { "${V[@]}" '~/oi/bin/monarchy-identity status --json'; }
has_account() { dc computer list | grep -qxF "$1"; }   # -F: the trailing $ of a computer name is not a regex anchor
pt() { "${V[@]}" "sudo python3 -I /tmp/pamtest.py $* 2>&1"; }
pam_stock() { "${V[@]}" "cat /etc/pam.d/system-auth" | diff -q - fixtures/pam.d/system-auth >/dev/null; }
untouched() { [[ $(st) == *'"enrolled":false'* ]] && pam_stock && ok "$1: machine untouched" || bad "$1: machine was modified"; }

scp -q -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P 2222 pamtest.py tester@127.0.0.1:/home/tester/
./deploy.sh --fixtures >/dev/null; "${V[@]}" 'sudo install -m 644 ~/pamtest.py /tmp/pamtest.py'
leave
trap 'dc ou delete "OU=Laptops,DC=corp,DC=test" >/dev/null; "${V[@]}" "sudo sysctl -qw kernel.hostname=oi-client" >/dev/null 2>&1; for c in "OI-CLIENT\$" "LAPTOP-0042\$"; do dc computer delete "$c" >/dev/null; done' EXIT

echo "[an existing computer account is never taken over silently]"
dc computer create OI-CLIENT >/dev/null
before=$(dc computer show 'OI-CLIENT$' | grep -E '^(pwdLastSet|whenChanged)' | sort)
out=$(enrol)
[[ $out == *"already exists in the directory"* && $out == *"DIFFERENT laptop"* ]] && ok "refused with an explanation (names the risk and both ways out)" || { bad "not refused: $out"; }
untouched "existing account"
has_account 'OI-CLIENT$' && ok "the other machine's account was NOT deleted by our rollback" || bad "pre-existing account deleted!"
[[ $(dc computer show 'OI-CLIENT$' | grep -E '^(pwdLastSet|whenChanged)' | sort) == "$before" ]] && ok "its password was not reset (the other laptop keeps working)" || bad "pre-existing account was modified"
out=$(enrol --replace-computer-account); [[ $out == *"enrolled in"* ]] && ok "--replace-computer-account enrols explicitly" || { bad "replace failed"; echo "$out" | sed 's/^/      /'; }
leave; has_account 'OI-CLIENT$' && bad "leave left the account" || ok "leave --admin removed it"

echo "[--computer-name]"
out=$(enrol --computer-name LAPTOP-0042); [[ $out == *"enrolled in CORP.TEST as LAPTOP-0042"* ]] && ok "enrol as LAPTOP-0042" || { bad "computer-name enrol"; echo "$out" | sed 's/^/      /'; }
has_account 'LAPTOP-0042$' && ok "directory has LAPTOP-0042\$ (not the hostname's account)" || bad "account missing"
has_account 'OI-CLIENT$' && bad "hostname-based account also created" || ok "no OI-CLIENT\$ created"
"${V[@]}" 'sudo faillock --user alice --reset' 2>/dev/null
[[ $(pt sddm alice "$PW") == ALLOWED* ]] && ok "directory login works under the custom computer name" || bad "login under custom name: $(pt sddm alice "$PW")"
[[ $("${V[@]}" 'sudo ~/oi/bin/monarchy-identity policy show' | grep computer) == *LAPTOP-0042* ]] && ok "policy show reports it" || bad "policy show"
leave; has_account 'LAPTOP-0042$' && bad "custom account left behind" || ok "leave removed LAPTOP-0042\$"
out=$(enrol --computer-name 'bad name;x'); [[ $out == *"invalid --computer-name"* ]] && ok "invalid --computer-name refused" || bad "bad name: $out"
out=$(enrol --computer-name TOO-LONG-COMPUTER-NAME); [[ $out == *"invalid --computer-name"* ]] && ok "over-long --computer-name refused" || bad "long name: $out"

echo "[hostnames that would collide across a fleet]"
for hn in omarchy archlinux localhost; do
  "${V[@]}" "sudo sysctl -qw kernel.hostname=$hn"
  out=$(enrol); [[ $out == *"generic '$hn'"* ]] && ok "generic hostname '$hn' refused" || bad "generic '$hn': $out"
done
"${V[@]}" "sudo sysctl -qw kernel.hostname=a-very-long-laptop-hostname-42"
out=$(enrol); [[ $out == *"longer than 15 characters"* ]] && ok "over-long hostname refused (would truncate and collide)" || bad "long hostname: $out"
untouched "bad hostnames"
out=$(enrol --computer-name LAPTOP-0099); [[ $out == *"enrolled in"* ]] && ok "...but an explicit --computer-name makes them usable" || bad "override with bad hostname: $out"
leave; dc computer delete 'LAPTOP-0099$' >/dev/null
"${V[@]}" "sudo sysctl -qw kernel.hostname=oi-client"

echo "[--ou]"
dc ou create "OU=Laptops,DC=corp,DC=test" >/dev/null
out=$(enrol --ou "OU=Laptops,DC=corp,DC=test"); [[ $out == *"enrolled in"* ]] && ok "enrol with --ou" || { bad "ou enrol"; echo "$out" | sed 's/^/      /'; }
dn=$(dc computer show 'OI-CLIENT$' | sed -n 's/^dn: //p')
[[ $dn == "CN=OI-CLIENT,OU=Laptops,DC=corp,DC=test" ]] && ok "computer account created in the OU: $dn" || bad "wrong DN: $dn"
"${V[@]}" 'sudo faillock --user alice --reset' 2>/dev/null
[[ $(pt sddm alice "$PW") == ALLOWED* ]] && ok "login works for a computer in an OU" || bad "login in OU"
leave
for badou in 'OU=Laptops' 'OU=x;rm -rf /,DC=corp,DC=test' $'OU=a\nOU=b,DC=corp,DC=test'; do
  out=$(enrol --ou "$badou"); [[ $out == *"invalid --ou"* ]] && ok "invalid --ou refused: $(printf %q "$badou")" || bad "bad ou accepted: $out"
done
untouched "invalid --ou"
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
