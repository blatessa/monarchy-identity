---
name: release
description: Cut a monarchy-identity release (version bump, tag, GitHub release with the Arch packages). Use only when the owner asks for a release.
---

# Releasing

Releases are outward-facing: confirm with the owner before tagging or pushing a tag.

1. Make sure `main` is green (`gh run list --limit 3`) and the lab suites passed for changes since the last tag (`lab-e2e` skill).
2. Bump `pkgver` (and reset `pkgrel=1`) in `packaging/PKGBUILD`; commit on `main`.
3. `git tag vX.Y.Z && git push origin main vX.Y.Z`. The tag must equal `v$pkgver`.
4. `.github/workflows/release.yml` runs CI, builds the packages, checks the tag matches `pkgver`, and creates a GitHub release with the `.pkg.tar.zst` files, `SHA256SUMS` and generated notes. Watch it: `gh run watch`.
5. Check the release: `gh release view vX.Y.Z` shows both packages (`monarchy-identity`, `monarchy-identity-shell`) and the sums.

If the workflow fails after the tag is pushed, fix forward with a new patch tag; don't move a published tag.
