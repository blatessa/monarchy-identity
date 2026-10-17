# Harness for the fast layer: the real CLI against a temp /etc with stub commands first on PATH, as root inside a
# user namespace (`unshare -r`). No VM, no real root. Source it: `source "$(dirname "$0")/lib.sh"`.
# Stubs live in stubs/ (their behaviour and where it was observed: docs/dev/findings.md). Every suite ends with `result`.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIX="$REPO/test/vm/fixtures"
OIBIN="$REPO/bin/monarchy-identity"
PW='Passw0rd!Test'
fail=0
ok()  { printf '  PASS %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }
check() { local desc=$1; shift; if "$@"; then ok "$desc"; else bad "$desc"; fi; }   # check DESC CMD...
result() { ((fail)) && { echo "RESULT: FAIL"; exit 1; }; echo "RESULT: ALL PASS"; }
unshare -r true 2>/dev/null || { echo "SKIP: 'unshare -r' is not allowed here (user namespaces disabled)"; exit 1; }

# sandbox: a fresh stock-Omarchy machine in a temp dir (PAM and SDDM fixtures from the lab, Arch's nsswitch).
sandbox() {
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  export ETC_T="$T/etc" MONARCHY_IDENTITY_ETC="$T/etc" MONARCHY_IDENTITY_ROOT="$REPO" HOME="$T/home"
  export MONARCHY_IDENTITY_CONF="$T/etc/monarchy-identity/config.toml" MONARCHY_IDENTITY_SDDM_CONF_D="$T/etc/sddm.conf.d"
  export MONARCHY_IDENTITY_SUDOERS="$T/etc/sudoers.d/50-monarchy-identity" MONARCHY_IDENTITY_SUDOERS_THEME="$T/etc/sudoers.d/51-monarchy-identity-theme" MONARCHY_IDENTITY_POLKIT="$T/etc/polkit-1/rules.d/49-monarchy-identity.rules" MONARCHY_IDENTITY_LOCK="$T/lock"
  export MONARCHY_IDENTITY_SDDM_THEMES="$T/themes" MONARCHY_IDENTITY_SSS_DIR="$T/sss"
  export STUB_STATE="$T/state" STUB_LOG="$T/calls.log" STUB_PW="$PW" STUB_HOSTNAME=oi-client
  export STUB_GROUPS=oi-laptop-users,oi-admins STUB_COMPUTERS="" PATH="$REPO/test/unit/stubs:$PATH"
  unset STUB_DC_DOWN STUB_VISUDO_FAIL STUB_KINIT_FAIL STUB_JOINED OI_ADMIN_PASSWORD_FILE
  mkdir -p "$T/etc/sudoers.d" "$T/etc/polkit-1/rules.d" "$T/state" "$T/home" "$T/sss/db" "$T/sss/mc" "$T/themes"
  cp -r "$FIX/pam.d" "$T/etc/pam.d"; cp -r "$FIX/sddm.conf.d" "$T/etc/sddm.conf.d"
  printf 'passwd: files systemd\ngroup: files [SUCCESS=merge] systemd\nshadow: files systemd\nhosts: files dns\n' > "$T/etc/nsswitch.conf"
  : > "$STUB_LOG"
}

# oi ARGS...: run the CLI as (fake) root with the password on stdin; sets OUT (stdout+stderr) and RC.
oi() { OUT=$(printf '%s\n' "${PWIN-$PW}" | unshare -r "$OIBIN" "$@" 2>&1); RC=$?; }
# oi_user ARGS...: same, without root (the real uid).
oi_user() { OUT=$(printf '%s\n' "$PW" | "$OIBIN" "$@" 2>&1 </dev/null); RC=$?; }
enroll() { oi enroll --realm CORP.TEST --server dc.corp.test --admin Administrator "$@"; }

# snap: every file that decides how someone signs in, and what the stubs hold (joined, sssd running). krb5.conf and
# smb.conf are left out: enroll writes them to talk to the directory, before it has checked anything.
snap() { (cd "$T" && find etc state -type f ! -name krb5.conf ! -name smb.conf | sort | xargs -r md5sum); }
# refused LABEL MESSAGE: the last oi run failed with MESSAGE and the machine is exactly as before (BEFORE=$(snap)).
refused() {
  [[ $RC -ne 0 && $OUT == *"$2"* ]] && ok "$1: refused ('$2')" || { bad "$1: expected '$2' (rc $RC)"; tail -3 <<<"$OUT" | sed 's/^/      /'; }
  [[ $(snap) == "$BEFORE" ]] && ok "$1: nothing changed" || bad "$1: machine changed"
}
called() { grep -qF -- "$1" "$STUB_LOG"; }          # did a stub see this command line?
cfg() { grep -E "^$1 *=" "$MONARCHY_IDENTITY_CONF" | sed 's/^[^=]*= *"\(.*\)"$/\1/'; }   # a value in config.toml
has_pam() { python3 -I "$REPO/lib/pamedit.py" check "$T/etc/pam.d/$1"; }
