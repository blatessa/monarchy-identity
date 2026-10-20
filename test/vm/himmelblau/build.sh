#!/bin/bash
# The lab's himmelblau package: the omarchy-pkgs recipe plus the fixes below that upstream doesn't have yet
# (docs/dev/findings.md). Builds in a container, in images/himmelblau-build/, and leaves the package in images/.
#   himmelblau-4.0.6-change-password-joined.patch         himmelblau#1888
#   libhimmelblau-0.8.43-change-password-after-mfa.patch  libhimmelblau#109
#   himmelblau-4.0.6-max-tries.patch                      himmelblau#1895
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; I="$H/../images"; B="$I/himmelblau-build"
mkdir -p "$B" && cp "$H"/PKGBUILD "$H"/himmelblau.install "$H"/*.patch "$B"/
docker build -q -t oi-hbbuild -f "$H/Dockerfile.build" "$H" >/dev/null
docker run --rm -v "$B":/pkg -w /pkg oi-hbbuild bash -c \
  "useradd -m -u $(id -u) b 2>/dev/null; chown -R $(id -u) /pkg; su b -c 'makepkg -df --noconfirm -C' >makepkg.log 2>&1" \
  || { tail -20 "$B/makepkg.log"; exit 1; }
for p in "$B"/himmelblau-*.pkg.tar.zst; do cp "$p" "$I"/; echo "${p##*/}"; done
