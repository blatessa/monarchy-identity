# Writing a provider

A provider connects monarchy-identity to one kind of directory. Active Directory (`providers/ad/`) is the first; Entra
ID, Okta, Google Workspace and FreeIPA are equally first-class targets. Nothing outside `providers/<name>/` may assume a
particular directory.

## What the core owns, what the provider owns

| The core (same for every directory) | The provider |
|---|---|
| The CLI, locking, `status --json` top level | Registering the laptop with the directory (join, device registration, ...) and undoing it |
| Who may sign in: parsing and validating `--groups`, `--users`, `--mode any` | Making the laptop resolve directory users and groups (NSS) |
| `--sudo-groups`, `--offline-days`, autologin, login theme, `--if-needed`, `--password-file` | Naming the PAM module that authenticates them, and configuring it |
| Editing PAM with the provider's module, through `lib/pamedit.py` | Enforcing the resolved login policy with the directory's mechanism |
| SDDM, sudoers, the pacman/Omarchy hooks | Its own options (`--realm`, `--tenant`, ...) and their validation |
| The policy keys in `config.toml`, `provider` in `state.toml` | Its own keys in `state.toml`, its `details` health keys and its docs page |

`enroll` runs: the core validates the shared options, the provider's `enroll` registers and proves the directory
answers, then the core records the enrollment and switches sign-in on (PAM, autologin, sudoers, login theme).
`reassert` and `leave` wrap the provider's script the same way.

## Scripts

Each runs with `$OI_ROOT` set and sources `lib/common.sh` (`die`, `log`, `need_root`, `state_get`, `state_set`,
`read_admin_password`, ...). The core passes the resolved policy in the environment: `OI_LOGIN_MODE`
(`groups`, `assigned` or `any`), `OI_GROUPS`, `OI_USERS`, `OI_OFFLINE_DAYS`; and `MONARCHY_IDENTITY_PASSWORD_FILE` when
`--password-file` was given (`read_admin_password "PROMPT"` reads it, or standard input, asking PROMPT: name what you
need, such as "Client secret of the app registration").

| Script | Called by | Contract |
|---|---|---|
| `enroll [own options]` | `enroll <name>` | Validate its options, check everything the directory can reject, register, enforce the policy, make users resolve, wait until the directory answers. Must not touch PAM, SDDM or sudoers. Save what it needs to find the enrollment again with `state_set` (never in `config.toml`, which is the admin's). On success print one line naming the enrollment (`CORP.EXAMPLE.COM as LAPTOP-0042`). `--help` prints its options. |
| `matches [own options]` | `enroll --if-needed` on an enrolled laptop | Print the enrollment line if these options describe the current enrollment (the core then only converges the policy); fail with a clear message if not. |
| `policy show` | `policy show` | Print the provider's lines (the directory, the device name); the core prints the policy. |
| `policy apply` | `policy set`, `enroll --if-needed` | Enforce the resolved policy on an enrolled laptop; refuse (changing nothing) what the directory can't honour. |
| `reassert` | `reassert`, the update hooks | Idempotently re-apply the provider's edits (NSS, its daemon). |
| `unenroll [own options]` | `leave`, after the core removed PAM, SDDM and sudoers | Remove every other change `enroll` made, and what it created in the directory when it can. |
| `status` | `status` | Print read-only `key=value` health lines (`true`/`false`/`unknown`); they become `details`. |
| `detect` | (reserved) | Exit 0 if prerequisites are installed. |
| `pam.conf` (a file) | the core's PAM edit | `module = "pam_x.so"`, plus optional arguments per stack: `auth = "..."`, `account`, `password`, `session`; and `mkhomedir`, `expired_password_screen`, `auth_retry_on_abort`, `login_steps` for modules that need them ([The PAM edit](architecture.md#the-pam-edit)). |

The active provider is `provider` in `/var/lib/monarchy-identity/state.toml`. `test/unit/stub-provider/` is a complete
provider with no directory behind it, and `test/unit/provider.sh` checks the contract against it.

## Rules for every provider

- **Check against the directory before changing sign-in.** Anything the directory can reject (credentials, group
  names, name collisions) is checked before registering; PAM is edited last, after the directory demonstrably answers.
  A re-run after a failure must pick up where it stopped; no rollback machinery.
- **Never lock out local users.** The core inserts the module named in `pam.conf` with fixed rules (`-`-prefixed,
  unknown or unavailable users ignored), harmless when the module or its daemon is missing.
- **Same policy meaning everywhere.** `--groups` means "members of these directory groups", `--users` "only these
  people", default deny. If a directory can't express one of them, refuse it with a clear message in `enroll` and
  `policy apply`.
- **Offline sign-in.** Laptops travel: cached credentials after a first online sign-in are expected, with
  `--offline-days` honoured.
- **Validate input** before it reaches a config file; mark files you write with `$OI_MARK`.
- **No AUR dependencies.** If the directory's client is AUR-only, that's a decision for the owner before any code.
  The client is its own package and an `optdepends`, never bundled ([Directory clients](architecture.md#directory-clients)).
- **Stay in scope:** authentication and directory-provided authorization only ([Architecture](architecture.md#scope)).

## Things that differ between directories

Expect these to differ, and decide them per provider in its issue before writing code:

- **Registration.** AD joins a computer account with a password; cloud directories register a device (often with an
  admin consent or enrollment token); some need nothing per laptop.
- **How people authenticate.** Password checked by the directory (AD, FreeIPA, LDAP interfaces), or a browser/device
  flow with MFA (OIDC directories). The login screen and lock screen must still work.
- **User and group lookup.** Usernames may be emails; UIDs must still be stable across laptops.
- **What can be tested locally.** AD and FreeIPA run in containers; cloud directories need a test tenant or a
  documented stand-in. Each provider's issue says which.

## Done for a new provider

An e2e suite on `test/vm/lib.sh` (enroll, sign-in on every service, policy, a refused enroll, leave), the fast tests,
a page in `docs/providers/` (prepare the directory, prepare the laptops, options, troubleshooting, status details),
the provider listed on `docs/index.md` (Providers) and in the `mkdocs.yml` nav, and its files installed by the PKGBUILD.
