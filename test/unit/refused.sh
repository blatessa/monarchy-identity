#!/bin/bash
# Everything enroll must refuse before sign-in changes: no policy, bad input, wrong password, unknown group, DC down,
# colliding or generic computer names, unsafe password files. After every refusal the machine is exactly as before.
source "$(dirname "$0")/lib.sh"
sandbox
BEFORE=$(snap)
G=(--groups oi-laptop-users)

echo "[input]"
enroll;                                        refused "no policy"          "say who may sign in"
enroll --mode groups;                          refused "groups mode, no groups" "needs --groups"
enroll --mode assigned;                        refused "assigned mode, no users" "needs --users"
enroll "${G[@]}" --mode bogus;                 refused "bogus mode"         "bad --mode"
enroll "${G[@]}" --realm $'corp.test\n[evil]'; refused "realm injection"    "invalid --realm"
enroll --groups $'a\nsimple_allow_users = evil'; refused "group injection"  "invalid --groups"
enroll "${G[@]}" --sudo-groups 'x$(id)';       refused "sudo-groups"        "invalid --sudo-groups"
enroll "${G[@]}" --offline-days abc;           refused "offline-days"       "invalid --offline-days"
enroll "${G[@]}" --ou 'OU=x;rm -rf /,DC=corp,DC=test'; refused "ou"         "invalid --ou"
enroll "${G[@]}" --computer-name TOO-LONG-COMPUTER-NAME; refused "computer-name" "invalid --computer-name"
enroll "${G[@]}" --frobnicate;                 refused "unknown option"     "unknown option"
oi_user enroll --help; [[ $OUT == *"--groups a,b"* && $RC -eq 0 ]] && ok "enroll --help works without root" || bad "help: $OUT"
oi_user enroll ad --realm CORP.TEST "${G[@]}"; [[ $OUT == *"administrator rights"* ]] && ok "non-root refused" || bad "non-root: $OUT"

echo "[the directory says no]"
PWIN=wrong enroll "${G[@]}";                   refused "wrong password"     "wrong password, or no account named 'Administrator'"
PWIN=wrong enroll --mode any;                  refused "wrong password, no groups to check" "wrong password, or no account named 'Administrator'"
enroll --groups oi-laptop-users,no-such-group; refused "unknown group"      "has no group named: no-such-group"
STUB_DC_DOWN=1 enroll "${G[@]}";               refused "DC down"            "no domain controller answered at dc.corp.test"
STUB_NO_DNS=1 enroll "${G[@]}";                refused "DC name unresolvable" "'dc.corp.test' does not resolve"
STUB_NO_DNS=1 oi enroll ad --realm CORP.TEST --admin Administrator "${G[@]}"; refused "no DNS for the domain" "DNS has no domain controllers for corp.test"
STUB_JOIN_FAIL="Invalid configuration (\"workgroup\" set to 'X', should be 'CORP')" enroll "${G[@]}"
refused "join refused" "the directory refused the join: Invalid configuration (\"workgroup\" set to 'X', should be 'CORP')"
STUB_JOIN_FAIL='failed to precreate account in ou ou=Gone,dc=corp,dc=test: No such object' enroll "${G[@]}" --ou OU=Gone,DC=corp,DC=test
refused "join into a missing OU" "the directory has no OU 'OU=Gone,DC=corp,DC=test'"

echo "[computer names]"
: > "$STUB_LOG"
STUB_COMPUTERS=OI-CLIENT enroll "${G[@]}";     refused "another laptop's account" "DIFFERENT laptop"
called "net ads join" && bad "joined over another laptop's account" || ok "no join was attempted"
for hn in omarchy archlinux; do STUB_HOSTNAME=$hn enroll "${G[@]}"; refused "hostname $hn" "generic '$hn'"; done
STUB_HOSTNAME=a-very-long-laptop-hostname-42 enroll "${G[@]}"; refused "long hostname" "longer than 15 characters"

echo "[password sources]"
install -m 644 /dev/null "$T/open.pw"; echo "$PW" > "$T/open.pw"
enroll "${G[@]}" --password-file "$T/open.pw"; refused "world-readable password file" "accessible by group/other"
ln -s "$T/open.pw" "$T/link.pw"
enroll "${G[@]}" --password-file "$T/link.pw"; refused "symlinked password file" "not a regular file"
install -m 600 /dev/null "$T/empty.pw"
enroll "${G[@]}" --password-file "$T/empty.pw"; refused "empty password file" "empty"
OUT=$(unshare -r "$OIBIN" enroll ad --realm CORP.TEST --server dc.corp.test --admin Administrator "${G[@]}" </dev/null 2>&1); RC=$?
refused "no password at all" "must be given on stdin"
result
