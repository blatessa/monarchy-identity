# Compliance policy file

`/etc/monarchy-identity/policy.toml` defines what "compliant" means for [`monarchy-identity check`](cli.md#check).
An annotated example ships at `/usr/share/doc/monarchy-identity/policy.example.toml`.

## Format

Flat `key = value` lines. Values may be quoted. `#` starts a comment anywhere on a line, so values cannot contain
`#`. Blank lines are ignored. This is not full TOML: tables and arrays are not supported.

Only rules that appear in the file are checked. Unknown keys, malformed lines, bad values and an empty file are
errors (exit 2).

## Rules

| Key | Value | Passes when |
|---|---|---|
| `require_enrolled` | `true` | `enrolled` is true. |
| `require_self_heal` | `true` | `self_heal` is true. |
| `require_disk_encryption` | `true` | `compliance.disk_encryption` is `true`. |
| `require_firewall` | `true` | `compliance.firewall` is `active`. |
| `require_secure_boot` | `true` | `compliance.secure_boot` is `enabled`. |
| `require_tpm2` | `true` | `compliance.tpm2` is `present`. |
| `require_time_sync` | `true` | `compliance.time_sync` is `true`. |
| `forbid_autologin` | `true` | `autologin` is false. |
| `allowed_wheel_members` | comma list | Every member of `wheel` is in the list. |
| `max_screen_lock_seconds` | whole number | `compliance.screen_lock_seconds` is at most the value. |
| `required_login_mode` | `groups`, `assigned` or `any` | `login_mode` equals the value. |
| `unknown_is_failure` | `true` or `false` | Not a rule. Default `true`: `unknown` values fail their rule. With `false` they are reported `SKIP`. |

A boolean rule set to `false` is accepted and not checked.

`unknown` handling applies to the rules that read `compliance.*` values. `require_enrolled`, `require_self_heal`,
`forbid_autologin`, `allowed_wheel_members` and `required_login_mode` read fields that are always determined.

## Output

Human-readable: one line per rule (`PASS`, `FAIL` or `SKIP`, rule name, detail), then `COMPLIANT` or
`NON-COMPLIANT (N failed)`. With `--json`: `{"compliant": true|false, "results": [{"rule", "result", "detail"}]}`.

Exit codes: 0 compliant, 1 at least one `FAIL`, 2 bad policy or input.

## Example

```ini
require_enrolled        = true
require_self_heal       = true
require_disk_encryption = true
require_firewall        = true
require_time_sync       = true
forbid_autologin        = true
required_login_mode     = groups
allowed_wheel_members   = root
max_screen_lock_seconds = 600
```
