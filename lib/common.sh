# shared helpers for providers. Sourced, not executed.
OI_CONF="${MONARCHY_IDENTITY_CONF:-/etc/monarchy-identity/config.toml}"
OI_STATE="${MONARCHY_IDENTITY_STATE:-/var/lib/monarchy-identity}"
OI_ROOT="${OI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ETC="${MONARCHY_IDENTITY_ETC:-/etc}"   # overridable for tests

log() { echo "monarchy-identity: $*" >&2; logger -t monarchy-identity -- "$*" 2>/dev/null || true; }
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
# autologin.conf sorts after "99-...", so our override must sort after it: zz-monarchy-identity.conf.
SDDM_CONF_D="${MONARCHY_IDENTITY_SDDM_CONF_D:-/etc/sddm.conf.d}"
SDDM_OVERRIDE="$SDDM_CONF_D/zz-monarchy-identity.conf"

sddm_conf_value() { # sddm_conf_value Section Key -> effective value (last file wins, C-locale name order)
  local f val="" sect="" line
  while IFS= read -r f; do
    sect=""
    while IFS= read -r line; do
      line="${line%%#*}"; line="${line//[[:space:]]/}"
      case $line in
        \[*\]) sect=$line ;;
        "$2="*) [[ $sect == "[$1]" ]] && val=${line#"$2="} ;;
      esac
    done < "$f"
  done < <(LC_ALL=C ls -1 "$SDDM_CONF_D"/*.conf 2>/dev/null | LC_ALL=C sort)
  echo "$val"
}
sddm_autologin_user() { sddm_conf_value Autologin User; }   # prints the effective autologin user ("" if none)

sddm_autologin_disable() { # idempotent: only writes when content differs (a path unit watches this dir)
  local want=$'# managed by monarchy-identity: disables autologin on managed machines\n[Autologin]\nUser=\nSession=\n'
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

REVERT_UNIT="monarchy-identity-revert"
revert_schedule() { # minutes
  systemd-run --quiet --unit="$REVERT_UNIT" --on-active="${1}m" --description="monarchy-identity auto-revert (unconfirmed enrolment)" \
    env OI_ROOT="$OI_ROOT" "$OI_ROOT/bin/monarchy-identity" leave >/dev/null
}
revert_cancel()  { systemctl stop "$REVERT_UNIT.timer" "$REVERT_UNIT.service" 2>/dev/null || true; }
revert_pending() { systemctl is-active --quiet "$REVERT_UNIT.timer" 2>/dev/null; }

# --- serialization + self-heal watcher ----------------------------------------------------------
# Every state-changing command takes this lock, so the path-triggered reassert can never interleave
# with enroll/leave (it would otherwise re-add edits that leave is removing).
OI_LOCK="${MONARCHY_IDENTITY_LOCK:-/run/monarchy-identity.lock}"
oi_lock() { exec 9>"$OI_LOCK" && flock 9; }

WATCH_UNIT="monarchy-identity-reassert.path"
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

# --- SDDM login theme with a username field -----------------------------------------------------
# Omarchy's stock theme has no username box (it logs in userModel.lastUser), so directory users cannot
# sign in at the greeter. We select our own theme with a drop-in that sorts after Omarchy's.
SDDM_THEMES="${MONARCHY_IDENTITY_SDDM_THEMES:-/usr/share/sddm/themes}"
IDENTITY_THEME=monarchy-identity
SDDM_THEME_CONF="$SDDM_CONF_D/zz-monarchy-identity-theme.conf"
sddm_theme_installed() { [[ -f $SDDM_THEMES/$IDENTITY_THEME/Main.qml ]]; }
sddm_theme_effective() { sddm_conf_value Theme Current; }
sddm_theme_enable() { # idempotent; returns 1 if the theme package files are missing
  sddm_theme_installed || return 1
  local want=$'# managed by monarchy-identity: login screen with a username field\n[Theme]\nCurrent='"$IDENTITY_THEME"$'\n'
  install -d -m 0755 "$SDDM_CONF_D"
  [[ -f $SDDM_THEME_CONF && $(cat "$SDDM_THEME_CONF") == "${want%$'\n'}" ]] && return 0
  printf '%s' "$want" > "$SDDM_THEME_CONF"; chmod 0644 "$SDDM_THEME_CONF"
}
sddm_theme_restore() { rm -f "$SDDM_THEME_CONF"; }

# --- sudo for directory groups --------------------------------------------------------------------
# Optional: map directory groups to sudo via a sudoers drop-in. Validated with visudo BEFORE install
# (a broken sudoers file can lock out root access). Names are restricted so no escaping is needed.
SUDOERS_FILE="${MONARCHY_IDENTITY_SUDOERS:-/etc/sudoers.d/50-monarchy-identity}"
valid_sudo_groups() { local g IFS=,; [[ -n $1 ]] || return 1; for g in $1; do [[ $g =~ ^[A-Za-z0-9._-]{1,64}$ ]] || return 1; done; }
sudoers_apply() { # sudoers_apply "g1,g2"  -- idempotent: untouched file => no write (a path unit watches this dir)
  valid_sudo_groups "$1" || die "invalid --sudo-groups '$1' (letters, digits, . _ - only; no spaces)"
  local want g IFS=,
  want="# managed by monarchy-identity: directory groups with sudo"
  for g in $1; do want+=$'\n'"%$g ALL=(ALL:ALL) ALL"; done
  [[ -f $SUDOERS_FILE && $(cat "$SUDOERS_FILE") == "$want" && $(stat -c %a "$SUDOERS_FILE") == 440 ]] && return 0
  local tmp; tmp=$(mktemp "${SUDOERS_FILE}.XXXXXX") || die "cannot create temp sudoers file"
  printf '%s\n' "$want" > "$tmp"; chmod 0440 "$tmp"
  if command -v visudo >/dev/null 2>&1 && ! visudo -cf "$tmp" >/dev/null 2>&1; then rm -f "$tmp"; die "generated sudoers failed validation; not installed"; fi
  mv -f "$tmp" "$SUDOERS_FILE"
}
sudoers_remove() { rm -f "$SUDOERS_FILE"; }
