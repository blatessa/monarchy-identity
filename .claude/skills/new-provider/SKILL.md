---
name: new-provider
description: Add or change a directory provider under providers/ (for example FreeIPA or OIDC). Use when implementing a new provider or editing providers/sssd.
---

# Providers

A provider is `providers/<name>/` with executables `detect`, `enroll`, `unenroll`, `reassert`, `status` (plus `lib.sh`; the sssd provider also has `policy`). The CLI runs them via `run_provider` with `$OI_ROOT` set; they source `lib/common.sh`.

Contract:
- `detect`: exit 0 if prerequisites exist.
- `enroll`: validate every input first (see `test/unit/validation.sh`), refuse unsafe states (no local fallback account, colliding computer account, generic hostname), **prove the directory works before touching PAM**, then apply edits via `lib/pamedit.py`. Any failure rolls back everything, including directory objects it created (EXIT trap with an `enrolled_ok` flag; `die` calls `exit`, so an ERR trap never fires).
- `unenroll`: restore the pre-enrollment state exactly from `/var/lib/monarchy-identity/backup`.
- `reassert`: idempotently re-apply edits (self-heal calls it as root).
- `status`: print `key=value` lines; read-only, no root needed, `unknown` when undeterminable. Keys feed `status --json` (`details`).
- State goes in `/etc/monarchy-identity/config.toml` (flat `key = "value"`). Install every new file in `packaging/PKGBUILD`.

Do next: read `providers/sssd/enroll` end to end as the reference, follow the `pam-change` skill for any system edit, write an e2e suite in `test/vm/` (enroll, policy, drift, leave, failed-enroll-changes-nothing), add it to `test/run-all.sh`, and document it under the providers docs.
