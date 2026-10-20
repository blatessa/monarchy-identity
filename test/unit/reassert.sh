#!/bin/bash
# The update hooks (hooks/reassert.sh and the Omarchy post-update wrapper) with a stub monarchy-identity on PATH.
set -u
export OI_SUDO=env   # real hook uses `sudo -n`; tests run an unprivileged stub on PATH
H="$(cd "$(dirname "$0")/../../hooks" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; CALLS="$T/calls"
printf '#!/bin/bash\necho "$@" >> %s\nexit ${STUB_RC:-0}\n' "$CALLS" > "$T/bin/monarchy-identity"; chmod +x "$T/bin/monarchy-identity"
fail=0
export MONARCHY_IDENTITY_CONF="$T/no-config.toml"   # state is what tells the hook whether it is enrolled
check() { if eval "$2"; then printf '  PASS %s\n' "$1"; else printf '  FAIL %s\n' "$1"; fail=1; fi; }

printf 'provider = "local"\nlogin_mode = "none"\n' > "$T/local.toml"
printf 'provider = "ad"\nlogin_mode = "groups"\n' > "$T/enrolled.toml"

: > "$CALLS"; PATH="$T/bin:$PATH" MONARCHY_IDENTITY_STATE="$T/local.toml" "$H/reassert.sh" 2>/dev/null; rc=$?
check "local: exit 0" '[[ $rc -eq 0 ]]'; check "local: no call" '[[ ! -s $CALLS ]]'

: > "$CALLS"; PATH="$T/bin:$PATH" MONARCHY_IDENTITY_STATE="$T/missing.toml" "$H/reassert.sh" 2>/dev/null; rc=$?
check "missing conf: exit 0" '[[ $rc -eq 0 ]]'; check "missing conf: no call" '[[ ! -s $CALLS ]]'

: > "$CALLS"; PATH="$T/bin:$PATH" MONARCHY_IDENTITY_STATE="$T/enrolled.toml" "$H/reassert.sh" 2>/dev/null; rc=$?
check "enrolled: exit 0" '[[ $rc -eq 0 ]]'; check "enrolled: calls reassert" '[[ $(cat "$CALLS") == reassert ]]'

: > "$CALLS"; PATH="$T/bin:$PATH" STUB_RC=3 MONARCHY_IDENTITY_STATE="$T/enrolled.toml" "$H/reassert.sh" 2>/dev/null; rc=$?
check "enrolled+failing subcommand: still exit 0" '[[ $rc -eq 0 ]]'

printf 'provider = ad\n' > "$T/bad.toml"   # unquoted: not our format
: > "$CALLS"; PATH="$T/bin:$PATH" MONARCHY_IDENTITY_STATE="$T/bad.toml" "$H/reassert.sh" 2>"$T/err"; rc=$?
check "malformed conf: exit 0" '[[ $rc -eq 0 ]]'; check "malformed conf: no call, says why" '[[ ! -s $CALLS ]] && grep -q "line 1" "$T/err"'

# no CLI on PATH: use minimal PATH with only needed tools
mkdir -p "$T/min"; for b in bash readlink dirname logger cat; do ln -s "$(command -v $b)" "$T/min/$b" 2>/dev/null; done
PATH="$T/min" MONARCHY_IDENTITY_STATE="$T/enrolled.toml" "$H/reassert.sh" 2>/dev/null; rc=$?
check "enrolled, CLI missing: exit 0" '[[ $rc -eq 0 ]]'

# idempotent: twice
: > "$CALLS"; for _ in 1 2; do PATH="$T/bin:$PATH" MONARCHY_IDENTITY_STATE="$T/enrolled.toml" "$H/reassert.sh" 2>/dev/null; done
check "idempotent: 2 calls, both ok" '[[ $(wc -l < "$CALLS") -eq 2 ]]'

# wrapper
: > "$CALLS"; PATH="$T/bin:$PATH" MONARCHY_IDENTITY_STATE="$T/enrolled.toml" "$H/post-update.d/10-monarchy-identity-reassert" 2>/dev/null
check "wrapper delegates" '[[ $(cat "$CALLS") == reassert ]]'
((fail)) && { echo "RESULT: FAIL"; exit 1; }; echo "RESULT: ALL PASS"
