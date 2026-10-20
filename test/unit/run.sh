#!/bin/bash
# The fast layer: every unit suite, no lab, no root. Each suite has its own sandbox, so they run at the same time.
# Prints one line per suite (and what failed); exit 1 if any failed.
cd "$(dirname "$0")" || exit 1
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
suites=()
for s in *.sh; do
  [[ $s == lib.sh || $s == run.sh ]] && continue
  suites+=("$s")
  (start=$(date +%s%N); bash "$s" >"$out/$s" 2>&1; echo "$? $(( ($(date +%s%N)-start)/1000000 ))" >"$out/$s.rc") &
done
wait
rc=0
for s in "${suites[@]}"; do
  read -r r ms <"$out/$s.rc"
  if ((r == 0)) && ! grep -q '^  FAIL\|^FAIL' "$out/$s"; then st=PASS; else st=FAIL; rc=1; grep -E 'FAIL|SKIP|^      ' "$out/$s" | head -15; fi
  printf '%-4s %-16s %sms\n' $st "$s" "$ms"
done
exit $rc
