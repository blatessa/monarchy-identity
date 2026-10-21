# Writing a provider

A provider connects monarchy-identity to one kind of directory: `providers/<name>/`. Nothing outside it may assume a
particular directory.

| The core | The provider |
|---|---|
| CLI, locking, top level of `status --json` | Registering with the directory, and undoing it |
| Parsing and validating `--groups`, `--users`, `--mode any` | Making directory users and groups resolve (NSS) |
| `--sudo-groups`, `--offline-days`, autologin, login theme, `--if-needed`, `--password-file` | Naming and configuring its PAM module |
| PAM edits (`lib/pamedit.py`), SDDM, sudoers, polkit, hooks | Enforcing the resolved policy the directory's way |
| Policy keys in `config.toml`, `provider` in `state.toml` | Its own options, its `state.toml` keys, `details` keys, docs page |

`enroll`: the core validates shared options, the provider's `enroll` registers and proves the directory answers, then
the core records the enrollment and edits PAM, autologin, sudoers and the theme. `reassert` and `leave` wrap the
provider's scripts the same way.

## Scripts

Each runs with `$OI_ROOT` set and sources `lib/common.sh` (`die`, `log`, `need_root`, `state_get`, `state_set`,
`read_admin_password`, ...). The resolved policy comes in `OI_LOGIN_MODE` (`groups`, `assigned`, `any`), `OI_GROUPS`,
`OI_USERS`, `OI_OFFLINE_DAYS`; `MONARCHY_IDENTITY_PASSWORD_FILE` when `--password-file` was given
(`read_admin_password "PROMPT"` reads it, or stdin).

| Script | Called by | Contract |
|---|---|---|
| `enroll [opts]` | `enroll <name>` | Validate options; check everything the directory can reject; register; enforce the policy; make users resolve; wait until the directory answers. No PAM, SDDM or sudoers. State via `state_set`. Print one line naming the enrollment. `--help`. |
| `matches [opts]` | `enroll --if-needed`, enrolled | Print the enrollment line if the options describe the current enrollment; else fail with why. |
| `policy show` / `policy apply` | `policy show`, `policy set`, `--if-needed` | Print its lines / enforce the resolved policy; refuse, changing nothing, what the directory can't do. |
| `reassert` | `reassert`, hooks | Re-apply its edits (NSS, daemon), idempotently. |
| `unenroll [opts]` | `leave`, after the core's removals | Remove every other change `enroll` made. |
| `status` | `status` | Read-only `key=true`, `false` or `unknown` lines; they become `details`. |
| `pam.conf` | the core's PAM edit | `module = "pam_x.so"`, optional `auth`, `account`, `password`, `session` arguments, and the switches in [The PAM edit](architecture.md#the-pam-edit). |

The active provider is `provider` in `/var/lib/monarchy-identity/state.toml`. `test/unit/stub-provider/` is a complete
provider with no directory; `test/unit/provider.sh` checks the contract against it.

## Rules

- Check against the directory before changing sign-in; PAM is edited last. A re-run after a failure picks up where it
  stopped (no rollback).
- The core inserts the module with fixed `-`-prefixed rules that ignore unknown users and a missing module or daemon.
- `--groups` and `--users` mean the same everywhere, default deny. What a directory can't express is refused in
  `enroll` and `policy apply`.
- Cached sign-in after a first online sign-in, with `--offline-days` honoured or refused.
- Validate input before it reaches a config file; mark written files with `$OI_MARK`.
- No AUR dependencies without an owner decision; the client is its own package and an `optdepends`.
- Scope: [Architecture](architecture.md#scope).

## Decide per provider, in its issue

Registration (computer account, device, nothing), how people authenticate (password to the directory, or a device or
browser flow with MFA; the login and lock screens must still work), user and group lookup (emails as names; UIDs stable
across laptops), and how to test it (a container, or a test tenant).

## Done

An e2e suite on `test/vm/lib.sh` (enroll, sign-in on every service, policy, a refused enroll, leave), unit tests, a
`docs/providers/` page (prepare, options, behaviour, troubleshooting, status details), an entry in `docs/index.md` and
`mkdocs.yml`, and its files installed by the PKGBUILD.
