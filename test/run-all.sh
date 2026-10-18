#!/bin/bash
# Run the fast layer, then the default lab suites, and summarize. Needs the lab (test/lab-check.sh).
# The login-screen suite (test/vm/e2e-greeter.sh) is its own run: do it when the SDDM theme or greeter changed.
cd "$(dirname "$0")/.."
suites=(
  "bash hooks/test-reassert.sh"
  "test/unit/run.sh"
  "test/vm/e2e.sh"
  "test/vm/e2e-offline.sh"
  "test/vm/e2e-dns.sh"
  "test/vm/e2e-package.sh"
)
echo "lab: verifying directory users/groups"; test/dc/seed-users.sh >/dev/null || { echo "lab directory is not in the expected state"; exit 1; }
rc=0; summary=()
for s in "${suites[@]}"; do
  log=$(mktemp); start=$(date +%s)
  if $s >"$log" 2>&1 && ! grep -q 'RESULT: FAIL\|^FAIL' "$log"; then r=PASS; else r=FAIL; rc=1; fi
  summary+=("$(printf '%-4s %-34s %ss' $r "$s" $(( $(date +%s)-start )))")
  [[ $r == FAIL ]] && { echo "----- $s FAILED:"; grep -E 'FAIL|ERROR' "$log" | head -15; }
  rm -f "$log"
done
echo; printf '%s\n' "${summary[@]}"; exit $rc
