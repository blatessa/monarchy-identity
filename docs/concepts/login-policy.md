# Login policy

The login policy decides which directory users may sign in on this machine. It is set at enrollment with `--mode` and
changed later with [`policy set`](../guides/change-policy.md).

| Mode | Who may sign in | Required option | sssd setting |
|---|---|---|---|
| `groups` | Members of the listed directory groups | `--groups a,b` | `access_provider = simple`, `simple_allow_groups` |
| `assigned` | Only the listed users | `--users u1,u2` | `access_provider = simple`, `simple_allow_users` |
| `any` | Every user in the directory | none | `access_provider = permit` |

`groups` is the default mode, and it requires `--groups`: there is no mode that allows everyone by default.
`any` must be requested explicitly.

## How it is enforced

Enforcement happens in the PAM account stage through `pam_sss`. Every service that includes Omarchy's `system-auth`
gets the same decision (tested: `sddm`, `sudo`, `login`, `sshd`, `system-remote-login`). The lock screen uses its own
PAM service, `omarchy-lock-password`, which is edited the same way.

A user who authenticates correctly but is not permitted is refused at the account stage. The [test evidence](../evidence.md) shows a
correct password being accepted by `pam_sss(auth)` and the sign-in then refused by `pam_sss(account)`
([Evidence](../evidence.md)).

## What the policy does not govern

- **Local accounts.** `pam_sss` is consulted first, ignores users it does not know, and the stack falls through to
  `pam_unix` unchanged. A local break-glass account works in every mode, including when sssd is stopped or the
  directory is unreachable.
- **`su`.** It uses `pam_unix` directly, so directory users cannot `su`.
- **Directory-side rules.** GPO-based access control is disabled (`ad_gpo_access_control = disabled`).

## Names

sssd runs with `use_fully_qualified_names = False`, so users and groups are short names (`alice`, `laptop-users`),
and home directories are `/home/<name>`. Group and user lists accept letters, digits and `. _ - @ \` and spaces
inside a name, separated by commas.

## Offline sign-in

`cache_credentials = True`: a user who has signed in on this machine can sign in again while the domain controller is
unreachable. A user never seen before cannot. `--offline-days N` makes cached credentials expire after N days
without reaching a DC (`offline_credentials_expiration`); the default is no expiry.
