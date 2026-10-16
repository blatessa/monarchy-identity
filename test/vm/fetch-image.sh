#!/bin/bash
# Download + verify the Arch cloud image into its own directory.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)/images"; mkdir -p "$D"
B=https://geo.mirror.pkgbuild.com/images/latest
cd "$D"
curl -fLO "$B/Arch-Linux-x86_64-cloudimg.qcow2"
curl -fLO "$B/Arch-Linux-x86_64-cloudimg.qcow2.SHA256"
sha256sum -c Arch-Linux-x86_64-cloudimg.qcow2.SHA256
