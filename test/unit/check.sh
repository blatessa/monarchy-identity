#!/bin/bash
# Unit tests for lib/check.py (policy evaluation). No VM, no root. Run: test/unit/check.sh
cd "$(dirname "$0")/../.." || exit 1
CHECK="python3 -I lib/check.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0

GOOD='{"enrolled":true,"self_heal":true,"autologin":false,"login_mode":"groups","wheel_members":"root,admin",
 "compliance":{"disk_encryption":"true","firewall":"active","secure_boot":"enabled","tpm2":"present","screen_lock_seconds":"300"}}'

# t <expected exit> <description> <status-json> <policy text>
t() {
  local want=$1 desc=$2 json=$3 pol=$4 got
  printf '%s\n' "$pol" > "$T/p.toml"
  printf '%s' "$json" | $CHECK "$T/p.toml" >/dev/null 2>&1; got=$?
  [[ $got == "$want" ]] && printf 'ok   %s\n' "$desc" || { printf 'FAIL %s (want exit %s, got %s)\n' "$desc" "$want" "$got"; fail=1; }
}
mod() { python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); exec(sys.argv[2]); print(json.dumps(d))' "$GOOD" "$1"; }

ALL='require_enrolled = true
require_self_heal = true
require_disk_encryption = true
require_firewall = true
require_secure_boot = true
require_tpm2 = true
forbid_autologin = true
allowed_wheel_members = root,admin
max_screen_lock_seconds = 600
required_login_mode = groups'

t 0 "fully compliant machine passes every rule" "$GOOD" "$ALL"
t 1 "not enrolled fails"            "$(mod 'd["enrolled"]=False')"                      "require_enrolled = true"
t 1 "self-heal off fails"           "$(mod 'd["self_heal"]=False')"                     "require_self_heal = true"
t 1 "no disk encryption fails"      "$(mod 'd["compliance"]["disk_encryption"]="false"')" "require_disk_encryption = true"
t 1 "firewall inactive fails"       "$(mod 'd["compliance"]["firewall"]="inactive"')"   "require_firewall = true"
t 1 "secure boot disabled fails"    "$(mod 'd["compliance"]["secure_boot"]="disabled"')" "require_secure_boot = true"
t 1 "no tpm2 fails"                 "$(mod 'd["compliance"]["tpm2"]="absent"')"         "require_tpm2 = true"
t 1 "autologin on fails"            "$(mod 'd["autologin"]=True')"                      "forbid_autologin = true"
t 1 "extra wheel member fails"      "$(mod 'd["wheel_members"]="root,admin,mallory"')"  "allowed_wheel_members = root,admin"
t 0 "wheel subset of allowed passes" "$(mod 'd["wheel_members"]="root"')"               "allowed_wheel_members = root,admin"
t 1 "lock timeout too long fails"   "$(mod 'd["compliance"]["screen_lock_seconds"]="1800"')" "max_screen_lock_seconds = 600"
t 0 "lock timeout exactly at max passes" "$(mod 'd["compliance"]["screen_lock_seconds"]="600"')" "max_screen_lock_seconds = 600"
t 1 "wrong login mode fails"        "$(mod 'd["login_mode"]="any"')"                    "required_login_mode = groups"

echo "-- unknown values"
UNK='d["compliance"]["disk_encryption"]="unknown"; d["compliance"]["screen_lock_seconds"]="unknown"'
t 1 "unknown fails by default (proof is required)"   "$(mod "$UNK")" $'require_disk_encryption = true\nmax_screen_lock_seconds = 600'
t 0 "unknown skipped with unknown_is_failure=false"  "$(mod "$UNK")" $'require_disk_encryption = true\nmax_screen_lock_seconds = 600\nunknown_is_failure = false'
t 1 "unknown_is_failure=false does not excuse real failures" "$(mod 'd["autologin"]=True')" $'forbid_autologin = true\nunknown_is_failure = false'

echo "-- a bad policy must fail loudly (exit 2), never silently weaken enforcement"
t 2 "typo in rule name"             "$GOOD" "require_disk_encrpytion = true"
t 2 "non-boolean value"             "$GOOD" "require_firewall = yes"
t 2 "non-numeric lock seconds"      "$GOOD" "max_screen_lock_seconds = soon"
t 2 "invalid login mode"            "$GOOD" "required_login_mode = everyone"
t 2 "unparseable line"              "$GOOD" "this is not a rule"
t 2 "empty policy (nothing checked)" "$GOOD" "# only a comment"
t 2 "invalid status JSON"           "not json" "require_firewall = true"
printf '%s' "$GOOD" | $CHECK "$T/missing.toml" >/dev/null 2>&1; [[ $? == 2 ]] && echo "ok   missing policy file" || { echo "FAIL missing policy file"; fail=1; }

echo "-- machine-readable output"
printf 'require_firewall = true\nrequire_tpm2 = true\n' > "$T/p.toml"
out=$(printf '%s' "$(mod 'd["compliance"]["tpm2"]="absent"')" | $CHECK "$T/p.toml" --json)
python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["compliant"] is False and {r["rule"]:r["result"] for r in d["results"]}=={"require_firewall":"PASS","require_tpm2":"FAIL"}' "$out" \
  && echo "ok   --json reports compliant:false with per-rule results" || { echo "FAIL --json output: $out"; fail=1; }
exit $fail
