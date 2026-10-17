# Shared helpers for the e2e suites. Source it from a suite in test/vm/: `source "$(dirname "$0")/lib.sh"`.
# Needs the lab (test/lab-check.sh). Every suite ends with `result`, which prints RESULT: ALL PASS or RESULT: FAIL.
set -u
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$H"
SSHO=(-i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=8)
V=(ssh "${SSHO[@]}" -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'
LAB="--realm CORP.TEST --server dc.corp.test --admin Administrator"
fail=0

ok()  { printf '  PASS %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }
check() { local desc=$1; shift; if "$@"; then ok "$desc"; else bad "$desc"; fi; }   # check DESC CMD...
result() { ((fail)) && { echo "RESULT: FAIL"; exit 1; }; echo "RESULT: ALL PASS"; }

q() { local o="" a; for a in "$@"; do o+=" $(printf '%q' "$a")"; done; printf '%s' "$o"; }   # quote for the remote shell
cli()  { "${V[@]}" "~/oi/bin/monarchy-identity$(q "$@")" 2>&1; }                              # as tester
scli() { "${V[@]}" "sudo ~/oi/bin/monarchy-identity$(q "$@")" 2>&1; }                         # as root
st() { "${V[@]}" '~/oi/bin/monarchy-identity status --json'; }
dc() { docker exec oi-test-dc samba-tool "$@" 2>&1; }
has_account() { dc computer list | grep -qxF "$1"; }   # -F: the $ of a computer name is not a regex anchor

# pt [--session] SERVICE USER PASSWORD [--chauthtok NEW]: runs the real PAM stack in the VM; prints ALLOWED/DENIED/...
pt() { "${V[@]}" "sudo python3 -I /tmp/pamtest.py$(q "$@")" 2>&1; }
expect() { local want=$1 desc=$2 out; shift 2; out=$(pt "$@"); [[ $out == "$want"* ]] && ok "$desc" || bad "$desc (got: ${out:-<nothing>})"; }
reset_locks() { "${V[@]}" 'for u in alice bob carol dave tester; do sudo faillock --user $u --reset 2>/dev/null; done; true'; }
pam_stock() { local f; for f in system-auth omarchy-lock-password; do "${V[@]}" "cat /etc/pam.d/$f" | diff -q - "fixtures/pam.d/$f" >/dev/null || return 1; done; }

# enroll [extra args]: enroll with the lab directory (password on stdin); prints the output. Faillock is reset after,
# because before enrollment directory users don't resolve and the reset is a silent no-op.
enroll() { local out; out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll$(q $LAB "$@")" 2>&1); reset_locks; printf '%s' "$out"; }
enroll_ok() { local out; out=$(enroll "$@"); [[ $out == *"enrolled in"* ]] && ok "enroll $*" || { bad "enroll $*"; sed 's/^/      /' <<<"$out"; }; }
leave() { echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1; }

# fresh: push the repo, reset PAM/SDDM to stock Omarchy, make sure the machine isn't enrolled.
fresh() {
  ./deploy.sh --fixtures >/dev/null
  scp -q "${SSHO[@]}" -P 2222 pamtest.py tester@127.0.0.1:/home/tester/ && "${V[@]}" 'sudo install -m 644 ~/pamtest.py /tmp/pamtest.py'
  leave
}
