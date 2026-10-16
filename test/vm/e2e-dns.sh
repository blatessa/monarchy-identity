#!/bin/bash
# Enrol WITHOUT --server (pure DNS SRV discovery, no /etc/hosts crutch). Needs DC (with DNS on 127.0.0.1:53) + VM.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
pt() { "${V[@]}" "sudo python3 -I ~/pamtest.py system-auth $1 '$2'" 2>&1; }
expect() { local out; out=$(pt "$2" "$3"); [[ $out == $1* ]] && ok "$4" || bad "$4 (got: $out)"; }
../dc/fix-dns.sh >/dev/null 2>&1
scp -q -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P 2222 pamtest.py tester@127.0.0.1:/home/tester/
./deploy.sh --fixtures >/dev/null
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
echo "[lab resolver: corp.test -> DC DNS; no hosts entry]"
"${V[@]}" 'sudo mkdir -p /etc/systemd/resolved.conf.d && printf "[Resolve]\nDNS=10.0.2.2\nDomains=~corp.test\n" | sudo tee /etc/systemd/resolved.conf.d/oi-lab.conf >/dev/null; sudo sed -i "/corp.test/d" /etc/hosts; sudo systemctl restart systemd-resolved; sleep 2'
"${V[@]}" 'getent hosts dc.corp.test' | grep -q 10.0.2.2 && ok "dc.corp.test resolves via DNS (hosts entry gone)" || bad "DNS resolution of dc.corp.test"
"${V[@]}" 'resolvectl query -t SRV _ldap._tcp.corp.test 2>&1' | grep -q 'dc.corp.test' && ok "SRV _ldap._tcp discovered" || bad "SRV lookup"
out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll sssd --realm CORP.TEST --admin Administrator --mode groups --groups oi-laptop-users" 2>&1)
[[ $out == *"enrolled in"* ]] && ok "enrol with NO --server" || { bad "enrol without --server"; echo "$out" | sed 's/^/      /'; }
"${V[@]}" 'sudo grep -c "^ad_server" /etc/sssd/sssd.conf' | grep -qx 0 && ok "sssd.conf has no ad_server (SRV discovery)" || bad "ad_server present"
"${V[@]}" 'for u in alice bob carol tester; do sudo faillock --user $u --reset; done' 2>/dev/null
expect ALLOWED alice "$PW" "alice allowed"
expect DENIED carol "$PW" "carol denied"
expect ALLOWED tester tester "local tester allowed"
echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
[[ $(docker exec oi-test-dc samba-tool computer list | grep -c OI-CLIENT) -eq 0 ]] && ok "leave (no server) removed computer account" || bad "computer account left behind"
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
