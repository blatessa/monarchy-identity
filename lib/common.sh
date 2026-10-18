# shared helpers for providers. Sourced, not executed.
OI_CONF="${MONARCHY_IDENTITY_CONF:-/etc/monarchy-identity/config.toml}"     # what the admin chose: who may sign in, desktop
OI_STATE="${MONARCHY_IDENTITY_STATE:-/var/lib/monarchy-identity/state.toml}" # what enroll did: provider, and the provider's keys
OI_ROOT="${OI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ETC="${MONARCHY_IDENTITY_ETC:-/etc}"   # overridable for tests

log() { echo "monarchy-identity: $*" >&2; logger -t monarchy-identity -- "$*" 2>/dev/null || true; }
die() { log "ERROR: $*"; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "this needs administrator rights: run it with sudo"; }

# --- config files ----------------------------------------------------------------------------------
# Two files, so an MDM can manage the admin's choices without touching the enrollment, and the other way round.
# config.toml, state.toml and the providers' pam.conf are a flat subset of TOML: `key = "value"` lines, # comments, blank lines.
# Values are basic strings with the escapes \" \\ \n \t. Anything else is refused with its line number rather than
# guessed at: these files decide who may sign in, and an MDM may write them.
declare -gA OI_KV=(); OI_KV_KEYS=()
OI_KV_LINE='^[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*=[[:space:]]*"(([^"\\]|\\.)*)"[[:space:]]*(#.*)?$'
kv_read() { # kv_read FILE: loads OI_KV and OI_KV_KEYS (in file order); empty if FILE is missing; dies on a bad line
  OI_KV=(); OI_KV_KEYS=()
  [[ -r $1 ]] || return 0
  local line n=0 key raw val i c
  while IFS= read -r line || [[ -n $line ]]; do
    ((++n))
    [[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
    [[ $line =~ $OI_KV_LINE ]] || die "$1 line $n is not key = \"value\""
    key=${BASH_REMATCH[1]} raw=${BASH_REMATCH[2]} val=""
    [[ -z ${OI_KV[$key]+set} ]] || die "$1 line $n sets '$key' a second time"
    for ((i = 0; i < ${#raw}; i++)); do
      c=${raw:i:1}
      if [[ $c == '\' ]]; then
        ((++i)); c=${raw:i:1}
        case $c in n) c=$'\n' ;; t) c=$'\t' ;; '"' | '\') ;; *) die "$1 line $n has an unknown escape '\\$c'" ;; esac
      fi
      val+=$c
    done
    OI_KV[$key]=$val; OI_KV_KEYS+=("$key")
  done < "$1"
}
kv_get() { # kv_get file key default: a value from a config file (the default when it is missing or empty)
  kv_read "$1"
  local v=${OI_KV[$2]-}
  printf '%s\n' "${v:-${3:-}}"
}
conf_get() { kv_get "$OI_CONF" "$@"; }   # conf_get key default
state_get() { # state_get key default; enrollments made before the split kept state in config.toml until state_migrate
  if [[ -e $OI_STATE ]]; then kv_get "$OI_STATE" "$@"; else kv_get "$OI_CONF" "$@"; fi
}
conf_check() { kv_read "$OI_CONF"; kv_read "$OI_STATE"; }   # dies on a malformed file (run in the main shell, not in $(...))

kv_write() { # kv_write FILE key=value ... (rewrites the whole file, 0644)
  local f=$1 kv k v out=""; shift
  for kv in "$@"; do
    k=${kv%%=*} v=${kv#*=}
    [[ $k =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid config key '$k'"
    v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//$'\n'/\\n}; v=${v//$'\t'/\\t}
    [[ ! $v =~ [[:cntrl:]] ]] || die "the value for $k has control characters"
    out+="$k = \"$v\""$'\n'
  done
  install -d -m 0755 "$(dirname "$f")"
  printf '%s' "$out" > "$f.tmp"
  chmod 0644 "$f.tmp"; mv "$f.tmp" "$f"
}
kv_set() { # kv_set FILE key=value ...: changes these keys and keeps the others
  local f=$1 kv k keep=(); shift; local new=" ${*%%=*} "
  kv_read "$f"
  for k in "${OI_KV_KEYS[@]}"; do [[ $new == *" $k "* ]] || keep+=("$k=${OI_KV[$k]}"); done
  kv_write "$f" "${keep[@]}" "$@"
}
conf_write() { kv_write "$OI_CONF" "$@"; }
conf_set() { kv_set "$OI_CONF" "$@"; }
state_set() { kv_set "$OI_STATE" "$@"; }

# The admin's keys; anything else in config.toml is enrollment state from before the split, which state_migrate moves
# (once, as root, before a command changes anything).
CONF_KEYS=" login_mode groups users sudo_groups offline_days autologin_disabled login_theme "   # login_theme: no longer written or read; kept so older configs keep it
state_migrate() {
  [[ ! -e $OI_STATE && -f $OI_CONF ]] || return 0
  local k conf=() state=()
  kv_read "$OI_CONF"
  for k in "${OI_KV_KEYS[@]}"; do
    if [[ $CONF_KEYS == *" $k "* ]]; then conf+=("$k=${OI_KV[$k]}"); else state+=("$k=${OI_KV[$k]}"); fi
  done
  ((${#state[@]})) || return 0
  kv_write "$OI_STATE" "${state[@]}"; kv_write "$OI_CONF" "${conf[@]}"
  log "moved enrollment state from $OI_CONF to $OI_STATE"
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
# pamedit.py adds the safety rules. Two switches for modules that already do these themselves (default "true"):
# mkhomedir = "false" (the module makes home directories), expired_password_screen = "false" (no change-password
# screen at the login screen); and auth_retry_on_abort = "true" for a module that aborts the first time the directory
# is unreachable and answers from its cache when asked again. Removal is by marker, so it needs no provider.
PAMEDIT="$OI_ROOT/lib/pamedit.py"
PAM_FILES=(system-auth omarchy-lock-password)
pam_apply() { # pam_apply PROVIDER
  local pc="$OI_ROOT/providers/$1/pam.conf" module t a f args=()
  module=$(kv_get "$pc" module "")
  [[ -n $module ]] || die "provider '$1' names no PAM module (expected module = \"pam_....so\" in $pc)"
  for t in auth account password session; do a=$(kv_get "$pc" "$t" ""); [[ -z $a ]] || args+=("$t=$a"); done
  local opt=()
  [[ $(kv_get "$pc" mkhomedir true) == true ]] || opt+=(--no-mkhomedir)
  [[ $(kv_get "$pc" auth_retry_on_abort false) != true ]] || opt+=(--retry-on-abort)
  for f in "${PAM_FILES[@]}"; do
    if [[ -f $ETC/pam.d/$f ]]; then python3 -I "$PAMEDIT" apply "${opt[@]}" "$ETC/pam.d/$f" "$module" "${args[@]}" || die "could not edit $ETC/pam.d/$f"; fi
  done
  if [[ $(kv_get "$pc" expired_password_screen true) == true ]]; then greeter_apply "$module" "$(kv_get "$pc" account "")"
  else greeter_remove; fi
}
greeter_remove() {
  [[ ! -f $ETC/pam.d/$GREETER_PAM ]] || python3 -I "$PAMEDIT" remove "$ETC/pam.d/$GREETER_PAM"
  remove_if_ours "$ETC/pam.d/$EXPIRED_PAM"; rm -f "$SDDM_SESSION_CONF"
}
pam_remove() {
  local f; for f in "${PAM_FILES[@]}"; do [[ -f $ETC/pam.d/$f ]] && python3 -I "$PAMEDIT" remove "$ETC/pam.d/$f"; done
  greeter_remove
}

# --- an expired password at the login screen ------------------------------------------------------------------------
# SDDM can't ask for a new password, so "must change it" would just be a failed sign-in. Its service gets two rules
# (pamedit.py greeter) that let such a sign-in through, marked; lib/password-expired re-checks through its own service
# (the provider's module alone); SDDM's session command (lib/sddm-session) shows the change-password screen
# before the desktop. password-expired knows the drop-in's path.
GREETER_PAM=sddm
EXPIRED_PAM=monarchy-identity-expired
SDDM_SESSION_CONF="$SDDM_CONF_D/zz-monarchy-identity-session.conf"
write_if_changed() { # write_if_changed FILE CONTENT: 0644, only when the content differs (the mtime means something)
  install -d -m 0755 "$(dirname "$1")"
  [[ -f $1 && $(cat "$1") == "$2" ]] && return 0
  printf '%s\n' "$2" > "$1"; chmod 0644 "$1"
}
greeter_apply() { # greeter_apply MODULE [ACCOUNT_ARGS]
  write_if_changed "$ETC/pam.d/$EXPIRED_PAM" "$OI_MARK: lib/password-expired asks the directory if a password must be changed
auth     required  $1
account  required  $1${2:+ $2}"
  write_if_changed "$SDDM_SESSION_CONF" "$OI_MARK: an expired password is changed before the desktop
[Wayland]
SessionCommand=$OI_ROOT/lib/sddm-session
[X11]
SessionCommand=$OI_ROOT/lib/sddm-session"
  [[ ! -f $ETC/pam.d/$GREETER_PAM ]] || python3 -I "$PAMEDIT" greeter "$ETC/pam.d/$GREETER_PAM" "$OI_ROOT/lib/password-expired" \
    || die "could not edit $ETC/pam.d/$GREETER_PAM"
}

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
# read_admin_password [PROMPT]: sets $pw from $MONARCHY_IDENTITY_PASSWORD_FILE (the core sets it from --password-file),
# else the first line of stdin, asking PROMPT on a terminal (the provider names what it needs).
# A password file must be a regular file owned by root or the caller with no group/other permissions.
read_admin_password() {
  local f=${MONARCHY_IDENTITY_PASSWORD_FILE:-} prompt=${1:-Password of the directory join account}
  if [[ -n $f ]]; then
    [[ -f $f && ! -L $f ]] || die "password file '$f' is not a regular file"
    local mode owner; mode=$(stat -c %a "$f"); owner=$(stat -c %u "$f")
    (( (8#$mode & 8#077) == 0 )) || die "password file '$f' is accessible by group/other (mode $mode); chmod 600 it"
    [[ $owner -eq 0 || $owner -eq $EUID ]] || die "password file '$f' must be owned by root or the invoking user"
    IFS= read -r pw < "$f" || [[ -n ${pw:-} ]] || die "password file '$f' is empty"
  else
    [[ ! -t 0 ]] || printf '%s: ' "$prompt" >&2
    IFS= read -r -s pw || die "${prompt,} must be given on stdin, --password-file, or MONARCHY_IDENTITY_PASSWORD_FILE"
    [[ ! -t 0 ]] || echo >&2
  fi
  [[ -n $pw ]] || die "empty ${prompt,}"
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
# or it would replace the local admins. Omarchy's prompt asks for the first identity offered and shows no choice, so
# an admin who asks is listed first: they answer with their own password, not the first local admin's. Only written
# where polkit's rules directory exists (it is root:polkitd 0750, so it is never created here); names are validated,
# so they can go into the JS as they are.
POLKIT_RULES_FILE="${MONARCHY_IDENTITY_POLKIT:-/etc/polkit-1/rules.d/49-monarchy-identity.rules}"
polkit_apply() { # polkit_apply "g1,g2"
  valid_sudo_groups "$1" || die "invalid --sudo-groups '$1' (letters, digits, . _ - only; no spaces)"
  [[ -d $(dirname "$POLKIT_RULES_FILE") ]] || return 0
  local groups='"wheel"' g IFS=,
  for g in $1; do groups+=", \"$g\""; done
  local want="// managed by monarchy-identity: directory groups with sudo may answer administrator prompts
polkit.addAdminRule(function(action, subject) {
    var groups = [$groups], ids = groups.map(function(g) { return \"unix-group:\" + g; });
    for (var i = 0; i < groups.length; i++)
        if (subject.isInGroup(groups[i])) return [\"unix-user:\" + subject.user].concat(ids);
    return ids;
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
