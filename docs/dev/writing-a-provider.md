# Writing a provider

A provider connects monarchy-identity to one kind of directory. Active Directory (`providers/ad/`) is the first; Entra
ID, Okta, Google Workspace and FreeIPA are equally first-class targets. Nothing outside `providers/<name>/` may assume a
particular directory.

## What the core owns, what the provider owns

| The core (same for every directory) | The provider |
|---|---|
| The CLI, locking, `status --json` top level | Registering the laptop with the directory (join, device registration, ...) and undoing it |
| Who may sign in: `--groups`, `--users`, `--mode any` | Making the laptop resolve directory users and groups (NSS) |
| `--sudo-groups`, `--offline-days`, autologin, login theme, `--if-needed` | Authenticating them (the PAM module, and its config) |
| Password-file handling (`read_admin_password`) | Enforcing the login policy with the directory's mechanism |
| Editing PAM through `lib/pamedit.py` | Its own options (`--realm`, `--tenant`, ...) and their validation |
| SDDM, sudoers, the pacman/Omarchy hooks | Its `details` health keys and its docs page |

Today the AD provider still parses the shared options itself and `pamedit.py` inserts `pam_sss` specifically. Moving
both into the core is the first provider-work issue; do it before adding a second provider rather than copying.

## Scripts

| Script | Called by | Contract |
|---|---|---|
| `enroll [args]` | `monarchy-identity enroll <name> [args]` | Register and turn on directory sign-in. |
| `unenroll [args]` | `leave` | Remove every change `enroll` made, and what it created in the directory when it can. |
| `policy show\|set ...` | `policy` | Show or change who may sign in. |
| `reassert` | `reassert`, the update hooks | Idempotently re-apply the edits. |
| `status` | `status` | Print read-only `key=value` health lines (`true`/`false`/`unknown`); they become `details`. |
| `detect` | (reserved) | Exit 0 if prerequisites are installed. |

The active provider is `provider` in `/etc/monarchy-identity/config.toml`; persist state there with `conf_write`.

## Rules for every provider

- **Check against the directory before changing sign-in.** Anything the directory can reject (credentials, group
  names, name collisions) is checked before registering; PAM is edited last, after the directory demonstrably answers.
  A re-run after a failure must pick up where it stopped; no rollback machinery.
- **Never lock out local users.** PAM rules go through `lib/pamedit.py`, `-`-prefixed, harmless when the module or
  its daemon is missing.
- **Same policy meaning everywhere.** `--groups` means "members of these directory groups", `--users` "only these
  people", default deny. If a directory can't express one of them, refuse it with a clear message.
- **Offline sign-in.** Laptops travel: cached credentials after a first online sign-in are expected, with
  `--offline-days` honoured.
- **Validate input** before it reaches a config file; mark files you write with `$OI_MARK`.
- **No AUR dependencies.** If the directory's client is AUR-only, that's a decision for the owner before any code.
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
the provider listed in `docs/providers/index.md`, and its files installed by the PKGBUILD.
