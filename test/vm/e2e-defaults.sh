#!/bin/bash
# Defaults over configuration: `enroll` without a provider or --mode, `--help` without root, a clear refusal when nobody
# is allowed, and the same implied mode for `policy set`. Needs DC + VM.
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
CLI='~/oi/bin/monarchy-identity'
A="--realm CORP.TEST --server dc.corp.test --admin Administrator"
./deploy.sh --fixtures >/dev/null
echo "$PW" | "${V[@]}" "sudo $CLI leave --admin Administrator" >/dev/null 2>&1

echo "[help needs no root]"
out=$("${V[@]}" "$CLI enroll --help" 2>&1); [[ $out == *"--groups a,b"* && $out == *"Who may sign in"* ]] && ok "enroll --help works unprivileged" || bad "help: $out"

echo "[nobody allowed by default]"
out=$(echo "$PW" | "${V[@]}" "sudo $CLI enroll $A" 2>&1); [[ $out == *"say who may sign in"* ]] && ok "no --groups/--users is refused with guidance" || bad "no-policy enroll: $out"
[[ $("${V[@]}" "$CLI status --json" | grep -c '"enrolled":false') == 1 ]] && ok "and nothing was changed" || bad "machine changed"

echo "[no provider, no --mode]"
out=$(echo "$PW" | "${V[@]}" "sudo $CLI enroll $A --groups oi-laptop-users" 2>&1)
[[ $out == *"enrolled in CORP.TEST"* && $out == *"login mode: groups"* ]] && ok "enroll --groups ... implies provider sssd and mode groups" || { bad "enroll: $out"; }

al() { "${V[@]}" "$CLI status --json" | grep -o '"autologin":[a-z]*'; }
[[ $(al) == '"autologin":false' ]] && ok "autologin is off by default after enrolling" || bad "autologin: $(al)"
[[ $("${V[@]}" "$CLI status") == *"revert pending:  false"* ]] && ok "status shows the revert timer state" || bad "status lacks revert pending"

echo "[policy set implies the mode]"
out=$(echo "$PW" | "${V[@]}" "sudo $CLI policy set --users alice" 2>&1); [[ $out == *"mode=assigned"* ]] && ok "--users alone switches to assigned" || bad "users: $out"
out=$(echo "$PW" | "${V[@]}" "sudo $CLI policy set --groups oi-laptop-users" 2>&1); [[ $out == *"mode=groups"* ]] && ok "--groups alone switches back to groups" || bad "groups: $out"

echo "$PW" | "${V[@]}" "sudo $CLI leave --admin Administrator" >/dev/null 2>&1
[[ $(al) == '"autologin":true' ]] && ok "leave restores Omarchy's autologin" || bad "autologin after leave: $(al)"
echo "[--keep-autologin]"
echo "$PW" | "${V[@]}" "sudo $CLI enroll $A --groups oi-laptop-users --keep-autologin" >/dev/null 2>&1
[[ $(al) == '"autologin":true' ]] && ok "--keep-autologin keeps it" || bad "keep: $(al)"
echo "$PW" | "${V[@]}" "sudo $CLI leave --admin Administrator" >/dev/null 2>&1
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
