#!/bin/bash
# Re-assert monarchy-identity /etc drop-ins after package updates.
# Shared by the alpm hook and hooks/post-update.d/*. Idempotent; exits 0 when not enrolled.
set -u

CONF="${MONARCHY_IDENTITY_CONF:-/etc/monarchy-identity/config.toml}"
TAG=monarchy-identity

log() { logger -t "$TAG" -- "reassert: $*" 2>/dev/null || true; echo "$TAG: reassert: $*" >&2; }

provider=""
if [[ -r $CONF ]]; then
  provider=$(sed -n 's/^provider[[:space:]]*=[[:space:]]*"\?\([^"]*\)"\?[[:space:]]*$/\1/p' "$CONF" | head -1)
fi

if [[ -z $provider || $provider == local ]]; then
  log "not enrolled (provider='${provider:-unset}'), nothing to do"
  exit 0
fi

if ! command -v monarchy-identity >/dev/null 2>&1; then
  log "provider '$provider' configured but monarchy-identity not on PATH, skipping"
  exit 0
fi

log "re-asserting provider '$provider'"
run=(monarchy-identity reassert)
if [[ $EUID -ne 0 ]]; then read -ra _sudo <<<"${OI_SUDO:-sudo -n}"; run=("${_sudo[@]}" monarchy-identity reassert); fi   # omarchy update keeps sudo alive; hooks run as the user
if "${run[@]}"; then
  log "done"
else
  rc=$?
  log "monarchy-identity reassert failed (rc=$rc)"
  exit 0   # never fail a package transaction / omarchy update over this
fi
