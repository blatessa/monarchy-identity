---
name: new-provider
description: Add or change a directory provider under providers/ (Entra ID, Okta, Google Workspace, FreeIPA, ...). Use when implementing a new provider or editing providers/ad.
---

# Providers

A provider is `providers/<name>/` with executables `detect`, `enroll`, `unenroll`, `reassert`, `status` (plus `lib.sh`; the ad provider also has `policy`). The CLI runs them via `run_provider` with `$OI_ROOT` set; they source `lib/common.sh`.

Contract:
- `detect`: exit 0 if prerequisites exist.
- `enroll`: validate every input first (see `test/unit/validation.sh`), check everything the directory can reject (credentials, group names, colliding computer account) **before joining**, and edit PAM last, via `lib/pamedit.py`. No rollback machinery: a re-run must pick up where a failed run stopped.
- `unenroll`: remove every change `enroll` made (marked PAM blocks, `$OI_MARK`-marked files, drop-ins).
- `reassert`: idempotently re-apply edits (the pacman hook calls it as root).
- `status`: print `key=value` lines; read-only, no root needed, `unknown` when undeterminable. Keys feed `status --json` (`details`).
- State goes in `/etc/monarchy-identity/config.toml` (flat `key = "value"`). Install every new file in `packaging/PKGBUILD`.

Read `docs/dev/writing-a-provider.md` first: it says what the core owns and what a provider owns. Every directory is first-class; nothing outside `providers/<name>/` may assume AD. Scope: a provider feature belongs here only if it authenticates or authorizes directory users (`docs/dev/architecture.md#scope`).

Do next: read `providers/ad/enroll` end to end as the reference, follow the `pam-change` skill for any system edit, write an e2e suite in `test/vm/` on `lib.sh` (enroll, policy, a refused enroll, leave), add it to `test/run-all.sh`, and document it in `docs/providers/` (user view) and `docs/dev/` (internals).
