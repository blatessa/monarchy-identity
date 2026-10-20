#!/bin/bash
# Build the real package from the working tree and install it in the VM (replaces any installed version).
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$H/../.." && pwd)"; cd "$H"
source ./ssh.sh
B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
rsync -a --exclude=.git --exclude=test "$R/" "$B/src/"
("$B/src/packaging/build-local.sh" --nodeps >"$B/build.log" 2>&1) || { tail "$B/build.log"; exit 1; }
PKG=$(ls "$B"/src/packaging/monarchy-identity-[0-9]*.pkg.tar.zst | head -1)
scp -q "${SSHO[@]}" -P 2222 "$PKG" tester@127.0.0.1:/home/tester/oi.pkg.tar.zst
ssh "${SSHO[@]}" -p 2222 tester@127.0.0.1 'sudo pacman -U --noconfirm oi.pkg.tar.zst >/dev/null 2>&1'
echo "package installed"
