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
5. Check the release: `gh release view vX.Y.Z` shows the `monarchy-identity` package and the sums.
6. Omarchy's package repo (`omacom/omarchy-pkgs`, `pkgbuilds/monarchy-identity/`) builds from the tag. The first time,
   the owner opens the PR there: our `PKGBUILD` and `monarchy-identity.install`, the checksum filled in (`updpkgsums`),
   and `.omarchy/package.json` with a `github` watch on `blatessa/monarchy-identity` (pattern
   `v(?P<version>[0-9]+(?:\.[0-9]+)*)`); `python helpers/upstream-watch.py check pkgbuilds/monarchy-identity` passes.
   After that their bot proposes each new tag; a change to our `PKGBUILD` or install file needs a PR there too (with
   `pkgrel` bumped at the same version).

If the workflow fails after the tag is pushed, fix forward with a new patch tag; don't move a published tag.
