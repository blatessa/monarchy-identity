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
