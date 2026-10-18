#!/bin/bash
# Re-assert monarchy-identity /etc drop-ins after package updates.
# Shared by the alpm hook and hooks/post-update.d/*. Idempotent; exits 0 when not enrolled.
set -u

TAG=monarchy-identity
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"   # the config reader (installed at ../lib, as in the repo)

log() { logger -t "$TAG" -- "reassert: $*" 2>/dev/null || true; echo "$TAG: reassert: $*" >&2; }

provider=$(conf_get provider "") || { log "cannot read $OI_CONF, skipping"; exit 0; }

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
