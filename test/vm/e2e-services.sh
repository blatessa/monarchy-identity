#!/bin/bash
# Policy + session (home dir creation) across Omarchy's real login services, plus SDDM autologin
# override. Needs DC + VM running.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
expect() { local out; out=$("${V[@]}" "sudo python3 -I ~/pamtest.py --session $3 $4 '$5'" 2>&1); [[ $out == $2* ]] && ok "$1" || bad "$1 (got: $out)"; }
al() { "${V[@]}" '~/oi/bin/omarchy-identity status --json' | grep -o '"autologin":[a-z]*'; }
enrol() { local out; out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/omarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users $*" 2>&1)
  [[ $out == *"enrolled in"* ]] && ok "enrol $*" || { bad "enrol $*"; echo "$out" | sed 's/^/      /'; }
  "${V[@]}" 'for u in alice bob carol tester; do sudo faillock --user $u --reset 2>/dev/null; done'; }
leave() { echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/omarchy-identity leave --admin Administrator' >/dev/null 2>&1; }

scp -q -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P 2222 pamtest.py tester@127.0.0.1:/home/tester/
./deploy.sh --fixtures >/dev/null
leave; "${V[@]}" 'sudo rm -rf /home/alice /home/bob /home/carol'

echo "[autologin override]"
[[ $(al) == '"autologin":true' ]] && ok "before: fixture autologin.conf active" || bad "before: $(al)"
enrol --disable-autologin
[[ $(al) == '"autologin":false' ]] && ok "effective autologin disabled" || bad "autologin still on: $(al)"
"${V[@]}" 'sudo rm -f /etc/sddm.conf.d/zz-omarchy-identity.conf'
[[ $(al) == '"autologin":true' ]] && ok "drift visible when override removed" || bad "drift not visible"
"${V[@]}" 'sudo ~/oi/bin/omarchy-identity reassert' >/dev/null 2>&1
[[ $(al) == '"autologin":false' ]] && ok "reassert restores override" || bad "reassert did not restore"
leave
[[ $(al) == '"autologin":true' ]] && ok "leave restores original autologin" || bad "leave left autologin off: $(al)"

echo "[services]"
enrol
for svc in sddm sudo login sshd system-remote-login; do
  expect "$svc: alice allowed (+session)" ALLOWED $svc alice "$PW"
  expect "$svc: carol denied" DENIED $svc carol "$PW"
  expect "$svc: bob wrong pw denied" DENIED $svc bob wrong
  expect "$svc: local tester allowed" ALLOWED $svc tester tester
done
echo "[home directories]"
perm=$("${V[@]}" 'sudo stat -c "%U %a" /home/alice 2>&1')
[[ $perm == "alice 700" ]] && ok "alice home created, owner alice, mode 700" || bad "alice home: $perm"
"${V[@]}" 'test -e /home/carol' && bad "denied user carol got a home dir" || ok "carol (denied) got no home dir"
leave
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
