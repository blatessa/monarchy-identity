#!/bin/bash
# Enroll WITHOUT --server: domain controllers found through DNS SRV records only. Needs DC (DNS on 127.0.0.1:53) + VM.
source "$(dirname "$0")/lib.sh"
../dc/fix-dns.sh >/dev/null 2>&1
fresh
echo "[lab resolver: corp.test -> the DC's DNS; no hosts entry]"
"${V[@]}" 'sudo mkdir -p /etc/systemd/resolved.conf.d && printf "[Resolve]\nDNS=10.0.2.2\nDomains=~corp.test\n" | sudo tee /etc/systemd/resolved.conf.d/oi-lab.conf >/dev/null; sudo sed -i "/corp.test/d" /etc/hosts; sudo systemctl restart systemd-resolved; sleep 2'
"${V[@]}" 'resolvectl query -t SRV _ldap._tcp.corp.test 2>&1' | grep -q dc.corp.test && ok "SRV _ldap._tcp.corp.test resolves" || bad "SRV lookup"
out=$(echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity enroll ad --realm CORP.TEST --admin Administrator --groups oi-laptop-users' 2>&1); reset_locks
[[ $out == *"enrolled in"* ]] && ok "enrolled with no --server" || { bad "enroll"; sed 's/^/      /' <<<"$out"; }
check "sssd.conf pins no server" "${V[@]}" '! sudo grep -q "^ad_server" /etc/sssd/sssd.conf'
expect ALLOWED "alice allowed" system-auth alice "$PW"
expect DENIED  "carol denied" system-auth carol "$PW"
leave
check "leave deleted the computer account" bash -c '! docker exec oi-test-dc samba-tool computer list | grep -qxF "OI-CLIENT\$"'
result
