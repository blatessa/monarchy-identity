#!/bin/bash
# Test reassert.sh with stub omarchy-identity on PATH. No system changes.
set -u
export OI_SUDO=env   # real hook uses `sudo -n`; tests run an unprivileged stub on PATH
H="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; CALLS="$T/calls"
printf '#!/bin/bash\necho "$@" >> %s\nexit ${STUB_RC:-0}\n' "$CALLS" > "$T/bin/omarchy-identity"; chmod +x "$T/bin/omarchy-identity"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

printf 'provider = "local"\nlogin_mode = "none"\n' > "$T/local.toml"
printf 'provider = "sssd"\nlogin_mode = "groups"\n' > "$T/sssd.toml"

: > "$CALLS"; PATH="$T/bin:$PATH" OMARCHY_IDENTITY_CONF="$T/local.toml" "$H/reassert.sh" 2>/dev/null; rc=$?
check "local: exit 0" '[[ $rc -eq 0 ]]'; check "local: no call" '[[ ! -s $CALLS ]]'

: > "$CALLS"; PATH="$T/bin:$PATH" OMARCHY_IDENTITY_CONF="$T/missing.toml" "$H/reassert.sh" 2>/dev/null; rc=$?
check "missing conf: exit 0" '[[ $rc -eq 0 ]]'; check "missing conf: no call" '[[ ! -s $CALLS ]]'

: > "$CALLS"; PATH="$T/bin:$PATH" OMARCHY_IDENTITY_CONF="$T/sssd.toml" "$H/reassert.sh" 2>/dev/null; rc=$?
check "enrolled: exit 0" '[[ $rc -eq 0 ]]'; check "enrolled: calls reassert" '[[ $(cat "$CALLS") == reassert ]]'

: > "$CALLS"; PATH="$T/bin:$PATH" STUB_RC=3 OMARCHY_IDENTITY_CONF="$T/sssd.toml" "$H/reassert.sh" 2>/dev/null; rc=$?
check "enrolled+failing subcommand: still exit 0" '[[ $rc -eq 0 ]]'

# no CLI on PATH: use minimal PATH with only needed tools
mkdir -p "$T/min"; for b in bash sed head logger cat; do ln -s "$(command -v $b)" "$T/min/$b" 2>/dev/null; done
PATH="$T/min" OMARCHY_IDENTITY_CONF="$T/sssd.toml" "$H/reassert.sh" 2>/dev/null; rc=$?
check "enrolled, CLI missing: exit 0" '[[ $rc -eq 0 ]]'

# idempotent: twice
: > "$CALLS"; for _ in 1 2; do PATH="$T/bin:$PATH" OMARCHY_IDENTITY_CONF="$T/sssd.toml" "$H/reassert.sh" 2>/dev/null; done
check "idempotent: 2 calls, both ok" '[[ $(wc -l < "$CALLS") -eq 2 ]]'

# wrapper
: > "$CALLS"; PATH="$T/bin:$PATH" OMARCHY_IDENTITY_CONF="$T/sssd.toml" "$H/post-update.d/10-omarchy-identity-reassert" 2>/dev/null
check "wrapper delegates" '[[ $(cat "$CALLS") == reassert ]]'
exit $fail
