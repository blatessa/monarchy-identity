#!/bin/bash
# The lab's himmelblau package: the omarchy-pkgs recipe (what people install), until Omarchy's repository
# has it. Builds in a container, in images/himmelblau-build/, and leaves the package in images/. Skips the build when
# images/ already has this version.
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; I="$H/../images"; B="$I/himmelblau-build"
v=$(sed -n 's/^pkgver=//p' "$H/PKGBUILD")-$(sed -n 's/^pkgrel=//p' "$H/PKGBUILD")
ls "$I"/himmelblau-"$v"-*.pkg.tar.zst >/dev/null 2>&1 && { echo "images/ has himmelblau $v"; exit 0; }
mkdir -p "$B" && cp "$H"/PKGBUILD "$H"/himmelblau.install "$B"/
docker build -q -t oi-hbbuild -f "$H/Dockerfile.build" "$H" >/dev/null
docker run --rm -v "$B":/pkg -w /pkg oi-hbbuild bash -c \
  "useradd -m -u $(id -u) b 2>/dev/null; chown -R $(id -u) /pkg; su b -c 'makepkg -df --noconfirm -C' >makepkg.log 2>&1" \
  || { tail -20 "$B/makepkg.log"; exit 1; }
for p in "$B"/himmelblau-"$v"-*.pkg.tar.zst; do cp "$p" "$I"/; echo "${p##*/}"; done
