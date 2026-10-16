# shared helpers for providers. Sourced, not executed.
OI_CONF="${OMARCHY_IDENTITY_CONF:-/etc/omarchy-identity/config.toml}"
OI_STATE="${OMARCHY_IDENTITY_STATE:-/var/lib/omarchy-identity}"
OI_ROOT="${OI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ETC="${OMARCHY_IDENTITY_ETC:-/etc}"   # overridable for tests

log() { echo "omarchy-identity: $*" >&2; logger -t omarchy-identity -- "$*" 2>/dev/null || true; }
die() { log "ERROR: $*"; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "must run as root"; }

conf_get() { # conf_get key default
  local v=""
  [[ -r $OI_CONF ]] && v=$(sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\?\([^\"]*\)\"\?$/\1/p" "$OI_CONF" | head -1)
  echo "${v:-$2}"
}

conf_write() { # conf_write key=value ... (rewrites whole file, root:root 0644)
  install -d -m 0755 "$(dirname "$OI_CONF")"
  : > "$OI_CONF.tmp"
  local kv; for kv in "$@"; do printf '%s = "%s"\n' "${kv%%=*}" "${kv#*=}" >> "$OI_CONF.tmp"; done
  chmod 0644 "$OI_CONF.tmp"; mv "$OI_CONF.tmp" "$OI_CONF"
}

# backup_file <path>: save the ORIGINAL once (never overwrite an existing backup).
backup_file() {
  local f=$1 d="$OI_STATE/backup"
  install -d -m 0700 "$d"
  local b="$d/$(echo "$f" | tr / _)"
  if [[ -e $f && ! -e $b ]]; then cp -a "$f" "$b"; elif [[ ! -e $f && ! -e $b && ! -e $b.absent ]]; then : > "$b.absent"; fi
}
restore_file() {
  local f=$1 b="$OI_STATE/backup/$(echo "$1" | tr / _)"
  if [[ -e $b ]]; then cp -a "$b" "$f"; elif [[ -e $b.absent ]]; then rm -f "$f"; fi
}

# --- SDDM autologin ---------------------------------------------------------------------------
# SDDM merges $SDDM_CONF_D/*.conf in C-locale name order; the LAST [Autologin] User= wins. Omarchy's
# autologin.conf sorts after "99-...", so our override must sort after it: zz-omarchy-identity.conf.
SDDM_CONF_D="${OMARCHY_IDENTITY_SDDM_CONF_D:-/etc/sddm.conf.d}"
SDDM_OVERRIDE="$SDDM_CONF_D/zz-omarchy-identity.conf"

sddm_autologin_user() { # prints the effective autologin user ("" if none)
  local f user="" sect="" line
  while IFS= read -r f; do
    sect=""
    while IFS= read -r line; do
      line="${line%%#*}"; line="${line//[[:space:]]/}"
      case $line in
        \[*\]) sect=$line ;;
        User=*) [[ $sect == "[Autologin]" ]] && user=${line#User=} ;;
      esac
    done < "$f"
  done < <(LC_ALL=C ls -1 "$SDDM_CONF_D"/*.conf 2>/dev/null | LC_ALL=C sort)
  echo "$user"
}

sddm_autologin_disable() { # idempotent: only writes when content differs (a path unit watches this dir)
  local want=$'# managed by omarchy-identity: disables autologin on managed machines\n[Autologin]\nUser=\nSession=\n'
  install -d -m 0755 "$SDDM_CONF_D"
  [[ -f $SDDM_OVERRIDE && $(cat "$SDDM_OVERRIDE") == "${want%$'\n'}" ]] && return 0
  printf '%s' "$want" > "$SDDM_OVERRIDE"; chmod 0644 "$SDDM_OVERRIDE"
}
sddm_autologin_restore() { rm -f "$SDDM_OVERRIDE"; }

# --- lockout safety -----------------------------------------------------------------------------
# Local accounts (files only, not sssd) a human could still log in with if the directory is broken:
# uid>=1000, a real shell, and a usable password hash in /etc/shadow.
local_fallback_users() {
  local name pw uid shell
  while IFS=: read -r name _ uid _ _ _ shell; do
    [[ $uid -ge 1000 && $uid -lt 60000 ]] || continue
    [[ $shell != */nologin && $shell != */false && -n $shell ]] || continue
    pw=$(getent -s files shadow "$name" 2>/dev/null | cut -d: -f2)
    [[ -n $pw && $pw != '!'* && $pw != '*'* ]] && echo "$name"
  done < <(getent -s files passwd)
}

REVERT_UNIT="omarchy-identity-revert"
revert_schedule() { # minutes
  systemd-run --quiet --unit="$REVERT_UNIT" --on-active="${1}m" --description="omarchy-identity auto-revert (unconfirmed enrolment)" \
    env OI_ROOT="$OI_ROOT" "$OI_ROOT/bin/omarchy-identity" leave >/dev/null
}
revert_cancel()  { systemctl stop "$REVERT_UNIT.timer" "$REVERT_UNIT.service" 2>/dev/null || true; }
revert_pending() { systemctl is-active --quiet "$REVERT_UNIT.timer" 2>/dev/null; }

# --- serialization + self-heal watcher ----------------------------------------------------------
# Every state-changing command takes this lock, so the path-triggered reassert can never interleave
# with enroll/leave (it would otherwise re-add edits that leave is removing).
OI_LOCK="${OMARCHY_IDENTITY_LOCK:-/run/omarchy-identity.lock}"
oi_lock() { exec 9>"$OI_LOCK" && flock 9; }

WATCH_UNIT="omarchy-identity-reassert.path"
watch_enable()  { systemctl cat "$WATCH_UNIT" >/dev/null 2>&1 && systemctl enable --now "$WATCH_UNIT" >/dev/null 2>&1 || true; }
watch_disable() { systemctl disable --now "$WATCH_UNIT" >/dev/null 2>&1 || true; }
watch_active()  { systemctl is-active --quiet "$WATCH_UNIT" 2>/dev/null; }

# --- admin credential input ---------------------------------------------------------------------
# read_admin_password [file]: sets $pw from FILE (or $OI_ADMIN_PASSWORD_FILE), else first line of stdin.
# A password file must be a regular file owned by root or the caller with no group/other permissions.
read_admin_password() {
  local f=${1:-${OI_ADMIN_PASSWORD_FILE:-}}
  if [[ -n $f ]]; then
    [[ -f $f && ! -L $f ]] || die "password file '$f' is not a regular file"
    local mode owner; mode=$(stat -c %a "$f"); owner=$(stat -c %u "$f")
    (( (8#$mode & 8#077) == 0 )) || die "password file '$f' is accessible by group/other (mode $mode); chmod 600 it"
    [[ $owner -eq 0 || $owner -eq $EUID ]] || die "password file '$f' must be owned by root or the invoking user"
    IFS= read -r pw < "$f" || [[ -n ${pw:-} ]] || die "password file '$f' is empty"
  else
    IFS= read -r -s pw || die "admin password must be given on stdin, --password-file, or OI_ADMIN_PASSWORD_FILE"
  fi
  [[ -n $pw ]] || die "empty admin password"
}
