# Writing a provider

A provider is `providers/<name>/` with these executables; the CLI runs them with `$OI_ROOT` set. `providers/sssd/` is
the reference.

| Script | Called by | Contract |
|---|---|---|
| `enroll [args]` | `monarchy-identity enroll <name> [args]` | Join and turn on directory sign-in. |
| `unenroll [args]` | `leave` | Remove every change `enroll` made. |
| `policy show\|set ...` | `policy` | Show or change who may sign in. |
| `reassert` | `reassert`, the update hooks | Idempotently re-apply the edits. |
| `status` | `status` | Print read-only `key=value` health lines (`true`/`false`/`unknown`); they become `details`. |
| `detect` | (reserved) | Exit 0 if prerequisites are installed. |

The active provider is `provider` in `/etc/monarchy-identity/config.toml`; persist your state there with
`conf_write key=value ...` (it rewrites the whole file).

## Rules

- **Check against the directory before changing sign-in.** Anything the directory can reject (credentials, group
  names, name collisions) is checked before the join; PAM is edited last, after the directory demonstrably answers.
- **Never lock out local users.** PAM edits go through `lib/pamedit.py`; every rule `-`-prefixed and harmless when the
  module or daemon is missing.
- **Validate input** before it reaches a config file: no newlines or metacharacters (`test/unit/validation.sh`).
- **Mark what you write** (`$OI_MARK`) so `unenroll` removes only your files.
- **Stay in scope**: a feature belongs in a provider when it's about authenticating or authorizing directory users
  (see [Architecture](architecture.md#scope)).
- Install every new file in `packaging/PKGBUILD`.

Add an e2e suite in `test/vm/` (enroll, policy, a refused enroll, leave) and a page under `docs/providers/`.
