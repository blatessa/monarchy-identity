---
name: new-provider
description: Add or change a directory provider under providers/ (Entra ID, Okta, Google Workspace, FreeIPA, ...). Use when implementing a new provider or editing providers/ad.
---

# Providers

A provider is `providers/<name>/` with executables `detect`, `enroll`, `matches`, `policy`, `unenroll`, `reassert`, `status` and a `pam.conf` naming its PAM module (plus `lib.sh`). The CLI runs them via `run_provider` with `$OI_ROOT` set; they source `lib/common.sh`. The core parses the shared options (who may sign in, sudo, offline days, autologin, theme, `--if-needed`, `--password-file`) and does PAM, SDDM and sudoers itself; the provider gets its own options plus `OI_LOGIN_MODE`/`OI_GROUPS`/`OI_USERS`/`OI_OFFLINE_DAYS`.

Contract (full table in `docs/dev/writing-a-provider.md`):
- `enroll`: validate its own options first, check everything the directory can reject (credentials, group names, colliding computer account) **before registering**, enforce the policy, prove the directory answers; never touch PAM (the core does it after). Print one line naming the enrollment. No rollback machinery: a re-run must pick up where a failed run stopped.
- `matches`, `policy show|apply`, `unenroll`, `reassert`, `status`, `detect`: see the doc. `test/unit/stub-provider/` is a minimal complete example; `test/unit/provider.sh` checks the contract.
- State goes in `/etc/monarchy-identity/config.toml` via `conf_set` (flat `key = "value"`). `packaging/PKGBUILD` copies `providers/` whole.

Read `docs/dev/writing-a-provider.md` first: it says what the core owns and what a provider owns. Every directory is first-class; nothing outside `providers/<name>/` may assume AD. Scope: a provider feature belongs here only if it authenticates or authorizes directory users (`docs/dev/architecture.md#scope`).

Do next: read `providers/ad/enroll` end to end as the reference, follow the `pam-change` skill for any system edit, write an e2e suite in `test/vm/` on `lib.sh` (enroll, policy, a refused enroll, leave), add it to `test/run-all.sh`, and document it in `docs/providers/` (user view) and `docs/dev/` (internals).
