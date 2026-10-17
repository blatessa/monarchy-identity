# Writing a provider

A provider is a directory `providers/<name>/` containing these executables. The core CLI finds them under
`$OI_ROOT/providers/` (`/usr/share/monarchy-identity` when installed).

| Script | Called by | Contract |
|---|---|---|
| `detect` | (reserved) | Exit 0 if the provider's prerequisites are installed. The core does not call it yet. |
| `enroll [args]` | `monarchy-identity enroll <name> [args]` | Enroll the machine. Receives all remaining arguments. |
| `unenroll [args]` | `monarchy-identity leave [args]` | Restore the pre-enrollment state exactly. |
| `policy show\|set ...` | `monarchy-identity policy ...` | Show or change the login policy. |
| `reassert` | `monarchy-identity reassert`, hooks, path unit | Idempotently re-apply managed edits. |
| `status` | `monarchy-identity status` | Print `key=value` lines; they become `details` in `status --json`. |

Which provider is used for `leave`, `policy`, `reassert` and `status` is read from `provider` in
`/etc/monarchy-identity/config.toml`. The core also reads `login_mode` from it for the posture report.

## Rules

- Source `lib/common.sh` for `log`, `die`, `need_root`, `conf_get`, `conf_write`, `backup_file`, `restore_file` and
  the SDDM, sudoers and lock helpers. `$OI_ROOT` is set by the CLI.
- **Verify before PAM.** `enroll` must confirm the directory works before touching any PAM file.
- **Roll back fully.** Use an `EXIT` trap with a success flag: `die` calls `exit`, which an `ERR` trap never sees.
  Remove anything created in the directory by the failed attempt.
- **Back up originals** with `backup_file` before changing anything, and restore them in `unenroll`.
- **Disable the watcher first.** `unenroll` must call `watch_disable` before removing edits, or the path unit
  re-adds them.
- **Validate input** before it reaches a configuration file. Reject newlines and metacharacters.
- **PAM edits** go through `lib/pamedit.py` (marked blocks, computed skip counts). Every rule must be `-`-prefixed
  and safe when the module is missing.
- Restart sssd only through `sssd_restart`; never run `sssctl` without `</dev/null` and `timeout`.
- Anything the CLI sources must also be installed by `packaging/PKGBUILD`.

Persist state with `conf_write key=value ...` (it rewrites the whole file, so pass every key you want to keep).
Use `providers/sssd/` as the reference implementation and `providers/local/` as the minimal one.
