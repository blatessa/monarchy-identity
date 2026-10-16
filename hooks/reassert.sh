#!/bin/bash
# Re-assert omarchy-identity /etc drop-ins after package updates.
# Shared by the alpm hook and hooks/post-update.d/*. Idempotent; exits 0 when not enrolled.
set -u

CONF="${OMARCHY_IDENTITY_CONF:-/etc/omarchy-identity/config.toml}"
TAG=omarchy-identity

log() { logger -t "$TAG" -- "reassert: $*" 2>/dev/null || true; echo "$TAG: reassert: $*" >&2; }

provider=""
if [[ -r $CONF ]]; then
  provider=$(sed -n 's/^provider[[:space:]]*=[[:space:]]*"\?\([^"]*\)"\?[[:space:]]*$/\1/p' "$CONF" | head -1)
fi

if [[ -z $provider || $provider == local ]]; then
  log "not enrolled (provider='${provider:-unset}'), nothing to do"
  exit 0
fi

if ! command -v omarchy-identity >/dev/null 2>&1; then
  log "provider '$provider' configured but omarchy-identity not on PATH, skipping"
  exit 0
fi

log "re-asserting provider '$provider'"
if omarchy-identity reassert; then
  log "done"
else
  rc=$?
  log "omarchy-identity reassert failed (rc=$rc)"
  exit 0   # never fail a package transaction / omarchy update over this
fi
