# shared helpers for providers. Sourced, not executed.
OI_CONF="${MONARCHY_IDENTITY_CONF:-/etc/monarchy-identity/config.toml}"
OI_ROOT="${OI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ETC="${MONARCHY_IDENTITY_ETC:-/etc}"   # overridable for tests

log() { echo "monarchy-identity: $*" >&2; logger -t monarchy-identity -- "$*" 2>/dev/null || true; }
die() { log "ERROR: $*"; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "this needs administrator rights: run it with sudo"; }

kv_get() { # kv_get file key default: a value from a flat `key = "value"` file
  local v=""
  [[ -r $1 ]] && v=$(sed -n "s/^$2[[:space:]]*=[[:space:]]*\"\?\([^\"]*\)\"\?$/\1/p" "$1" | head -1)
  echo "${v:-${3:-}}"
}
conf_get() { kv_get "$OI_CONF" "$@"; }   # conf_get key default

conf_write() { # conf_write key=value ... (rewrites whole file, root:root 0644)
  install -d -m 0755 "$(dirname "$OI_CONF")"
  : > "$OI_CONF.tmp"
  local kv; for kv in "$@"; do printf '%s = "%s"\n' "${kv%%=*}" "${kv#*=}" >> "$OI_CONF.tmp"; done
  chmod 0644 "$OI_CONF.tmp"; mv "$OI_CONF.tmp" "$OI_CONF"
}
conf_set() { # conf_set key=value ...: changes these keys and keeps the others (the core's and the provider's)
  local kv keep=()
  if [[ -r $OI_CONF ]]; then
    while IFS= read -r kv; do [[ " ${*%%=*} " == *" ${kv%%=*} "* ]] || keep+=("$kv"); done \
      < <(sed -n 's/^\([A-Za-z0-9_]*\)[[:space:]]*=[[:space:]]*"\?\([^"]*\)"\?$/\1=\2/p' "$OI_CONF")
  fi
  conf_write "${keep[@]}" "$@"
}

# Files we write carry this marker; `leave` deletes only files that have it.
OI_MARK="# managed by monarchy-identity"
remove_if_ours() { local f; for f in "$@"; do [[ -f $f ]] && grep -qF "$OI_MARK" "$f" && rm -f "$f"; done; return 0; }

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

sddm_autologin_disable() { # idempotent: only writes when content differs
  local want=$'# managed by monarchy-identity: disables autologin on managed machines\n[Autologin]\nUser=\nSession=\n'
  install -d -m 0755 "$SDDM_CONF_D"
  [[ -f $SDDM_OVERRIDE && $(cat "$SDDM_OVERRIDE") == "${want%$'\n'}" ]] && return 0
  printf '%s' "$want" > "$SDDM_OVERRIDE"; chmod 0644 "$SDDM_OVERRIDE"
}
sddm_autologin_restore() { rm -f "$SDDM_OVERRIDE"; }

# --- PAM -----------------------------------------------------------------------------------------
# Every Omarchy sign-in funnels into system-auth; the lock screen has its own service. The module comes from the
# provider's pam.conf (module = "pam_x.so", plus optional per-stack arguments: auth = "...", account = "...", ...);
# pamedit.py adds the safety rules. Removal is by marker, so it needs no provider.
PAMEDIT="$OI_ROOT/lib/pamedit.py"
PAM_FILES=(system-auth omarchy-lock-password)
pam_apply() { # pam_apply PROVIDER
  local pc="$OI_ROOT/providers/$1/pam.conf" module t a f args=()
  module=$(kv_get "$pc" module "")
  [[ -n $module ]] || die "provider '$1' names no PAM module (expected module = \"pam_....so\" in $pc)"
  for t in auth account password session; do a=$(kv_get "$pc" "$t" ""); [[ -z $a ]] || args+=("$t=$a"); done
  for f in "${PAM_FILES[@]}"; do
    if [[ -f $ETC/pam.d/$f ]]; then python3 -I "$PAMEDIT" apply "$ETC/pam.d/$f" "$module" "${args[@]}" || die "could not edit $ETC/pam.d/$f"; fi
  done
}
pam_remove() { local f; for f in "${PAM_FILES[@]}"; do [[ -f $ETC/pam.d/$f ]] && python3 -I "$PAMEDIT" remove "$ETC/pam.d/$f"; done; return 0; }

# --- who may sign in: names in --groups / --users ---------------------------------------------------
# These values end up in provider config files. Reject anything that could inject extra config lines or shell
# metacharacters; names are restricted to what directories really use.
valid_list()  { # comma-separated names; letters digits . _ - @ space \ ; no leading/trailing space, no empties
  local item IFS=,; [[ -n $1 ]] || return 1
  for item in $1; do
    [[ $item =~ ^[A-Za-z0-9._@\\-]([A-Za-z0-9._@\\ -]{0,126}[A-Za-z0-9._@\\-])?$ ]] || return 1
  done
  [[ $1 != *,, && $1 != ,* && $1 != *,  ]]
}

# --- serialization -------------------------------------------------------------------------------
# Every state-changing command takes this lock, so a post-update reassert can never interleave with
# enroll/leave (it would otherwise re-add edits that leave is removing).
OI_LOCK="${MONARCHY_IDENTITY_LOCK:-/run/monarchy-identity.lock}"
oi_lock() { exec 9>"$OI_LOCK" && flock 9; }

# --- admin credential input ---------------------------------------------------------------------
# read_admin_password [file]: sets $pw from FILE (or $OI_ADMIN_PASSWORD_FILE, which the core sets from --password-file),
# else first line of stdin.
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
    [[ ! -t 0 ]] || printf 'Password of the directory join account: ' >&2
    IFS= read -r -s pw || die "admin password must be given on stdin, --password-file, or OI_ADMIN_PASSWORD_FILE"
    [[ ! -t 0 ]] || echo >&2
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
sudoers_write() { # sudoers_write FILE CONTENT  -- idempotent: untouched file => no write; visudo-validated before it replaces anything
  local f=$1 want=$2
  [[ -f $f && $(cat "$f") == "$want" && $(stat -c %a "$f") == 440 ]] && return 0
  local tmp; tmp=$(mktemp "$f.XXXXXX") || die "cannot create temp sudoers file"
  printf '%s\n' "$want" > "$tmp"; chmod 0440 "$tmp"
  if command -v visudo >/dev/null 2>&1 && ! visudo -cf "$tmp" >/dev/null 2>&1; then rm -f "$tmp"; die "generated sudoers failed validation; not installed"; fi
  mv -f "$tmp" "$f"
}
sudoers_apply() { # sudoers_apply "g1,g2"
  valid_sudo_groups "$1" || die "invalid --sudo-groups '$1' (letters, digits, . _ - only; no spaces)"
  local want g IFS=,
  want="# managed by monarchy-identity: directory groups with sudo"
  for g in $1; do want+=$'\n'"%$g ALL=(ALL:ALL) ALL"; done
  sudoers_write "$SUDOERS_FILE" "$want"
}
sudoers_remove() { rm -f "$SUDOERS_FILE" "$THEME_SUDOERS_FILE"; polkit_remove; }

# Graphical "enter an administrator password" prompts take their admin identities from polkit, whose default (Omarchy
# ships it too) is the local group wheel, so a directory admin could use sudo but never answer one. Add the sudo groups.
# Polkit stops at the first rule that answers and the default is 50-, so ours sorts before it and names wheel as well,
# or it would replace the local admins. Only written where polkit's rules directory exists (it is root:polkitd 0750,
# so it is never created here); names are validated, so they can go into the JS as they are.
POLKIT_RULES_FILE="${MONARCHY_IDENTITY_POLKIT:-/etc/polkit-1/rules.d/49-monarchy-identity.rules}"
polkit_apply() { # polkit_apply "g1,g2"
  valid_sudo_groups "$1" || die "invalid --sudo-groups '$1' (letters, digits, . _ - only; no spaces)"
  [[ -d $(dirname "$POLKIT_RULES_FILE") ]] || return 0
  local ids='"unix-group:wheel"' g IFS=,
  for g in $1; do ids+=", \"unix-group:$g\""; done
  local want="// managed by monarchy-identity: directory groups with sudo may answer administrator prompts
polkit.addAdminRule(function(action, subject) {
    return [$ids];
});"
  [[ -f $POLKIT_RULES_FILE && $(cat "$POLKIT_RULES_FILE") == "$want" ]] && return 0
  local tmp; tmp=$(mktemp "$POLKIT_RULES_FILE.XXXXXX") || die "cannot create temp polkit rules file"
  printf '%s\n' "$want" > "$tmp"; chmod 0644 "$tmp"; mv -f "$tmp" "$POLKIT_RULES_FILE"
}
polkit_remove() { rm -f "$POLKIT_RULES_FILE"; }

# Omarchy repaints the browser accent on every theme switch through a helper that writes root-owned policy, and lets
# its own admins (%wheel) do that without a password; anyone else gets a graphical password prompt at every login.
# Directory groups can't be in wheel (and wheel is full sudo), so mirror that one narrow rule for the people who may
# sign in. Same command and argument shape as Omarchy's etc/sudoers.d/omarchy-theme-browser. Names outside the safe
# set are skipped (those people keep the prompt); --mode any has no one to name, so no rule.
THEME_SUDOERS_FILE="${MONARCHY_IDENTITY_SUDOERS_THEME:-/etc/sudoers.d/51-monarchy-identity-theme}"
sudoers_theme_apply() { # sudoers_theme_apply MODE "groups" "users"
  local who="" x IFS=,
  case $1 in
    groups)   for x in $2; do [[ $x =~ ^[A-Za-z0-9._-]{1,64}$ ]] && who+="${who:+,}%$x"; done;;
    assigned) for x in $3; do [[ $x =~ ^[A-Za-z0-9._-]{1,64}$ ]] && who+="${who:+,}$x"; done;;
  esac
  [[ -n $who ]] || { rm -f "$THEME_SUDOERS_FILE"; return 0; }
  sudoers_write "$THEME_SUDOERS_FILE" "# managed by monarchy-identity: Omarchy theme switching without a password prompt
$who ALL=(root) NOPASSWD: /usr/bin/omarchy-theme-set-browser-policy [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]"
}
