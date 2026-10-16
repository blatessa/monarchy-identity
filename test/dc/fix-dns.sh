#!/bin/bash
# Lab only: the DC's DNS advertises its container IP, unreachable from the QEMU guest (which only sees the
# host as 10.0.2.2). Point the DC's A record there so SRV-based discovery works end to end.
set -euo pipefail
PW='Passw0rd!Test'
old=$(docker exec oi-test-dc samba-tool dns query 127.0.0.1 corp.test dc A -U Administrator --password="$PW" 2>/dev/null | sed -n 's/.*A: \([0-9.]*\).*/\1/p' | head -1)
[[ $old == 10.0.2.2 ]] && { echo "dc A already 10.0.2.2"; exit 0; }
docker exec oi-test-dc samba-tool dns add 127.0.0.1 corp.test dc A 10.0.2.2 -U Administrator --password="$PW" >/dev/null
[[ -n $old ]] && docker exec oi-test-dc samba-tool dns delete 127.0.0.1 corp.test dc A "$old" -U Administrator --password="$PW" >/dev/null
echo "dc A: $old -> 10.0.2.2"
