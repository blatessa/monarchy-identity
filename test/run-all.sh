#!/bin/bash
# Run every suite and summarize. Needs the DC and VM up (see ../CLAUDE.md). ~6 minutes.
cd "$(dirname "$0")/.."
suites=(
  "bash hooks/test-reassert.sh"
  "bash shell-plugin/tests/run.sh"
  "test/unit/validation.sh"
  "test/unit/check.sh"
  "test/vm/e2e.sh"
  "test/vm/e2e-modes.sh"
  "test/vm/e2e-services.sh"
  "test/vm/e2e-dns.sh"
  "test/vm/e2e-noninteractive.sh"
  "test/vm/e2e-passwd.sh"
  "test/vm/e2e-sudo.sh"
  "test/vm/e2e-expired.sh"
  "test/vm/e2e-offline.sh"
  "test/vm/e2e-package.sh"
  "test/vm/e2e-failure.sh"
  "test/vm/e2e-safety.sh"
)
rc=0; summary=()
for s in "${suites[@]}"; do
  log=$(mktemp); start=$(date +%s)
  if $s >"$log" 2>&1 && ! grep -q 'RESULT: FAIL\|^FAIL' "$log"; then r=PASS; else r=FAIL; rc=1; fi
  summary+=("$(printf '%-4s %-34s %ss' $r "$s" $(( $(date +%s)-start )))")
  [[ $r == FAIL ]] && { echo "----- $s FAILED:"; grep -E 'FAIL|ERROR' "$log" | head -15; }
  rm -f "$log"
done
echo; printf '%s\n' "${summary[@]}"; exit $rc
