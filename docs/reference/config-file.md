# Configuration file

`/etc/monarchy-identity/config.toml` (root-owned, mode 0644) records the provider and the policy chosen at
enrollment. It is written by `enroll` and `policy set` and read by the CLI, the providers and the reassert hook.
Do not edit it by hand: change policy with [`policy set`](../guides/change-policy.md).

Format: flat `key = "value"` lines. The file is rewritten in full on each save. The package installs a default
containing only `provider = "local"` and `login_mode = "none"`; the file is marked `backup=` so pacman keeps local
changes.

## Keys written by the sssd provider

| Key | Values | Meaning |
|---|---|---|
| `provider` | `sssd`, `local` | Active provider. `local` means not enrolled. |
| `login_mode` | `groups`, `assigned`, `any`, `none` | Login policy. |
| `realm` | realm | The enrolled realm as given. |
| `server` | host or empty | Pinned DC; empty means DNS discovery. |
| `groups` | comma list | Permitted groups (`groups` mode). |
| `users` | comma list | Permitted users (`assigned` mode). |
| `autologin_disabled` | `true`, `false` | `--disable-autologin` was set. |
| `login_theme` | `identity`, `stock` | Whether the `monarchy-identity` SDDM theme is selected (`stock` = `--keep-login-theme`). |
| `sudo_groups` | comma list | Groups in the sudoers drop-in. |
| `offline_days` | number | Cached credential lifetime; `0` is unlimited. |
| `computer_name` | NetBIOS name | The computer account. |
| `ou` | DN or empty | OU the account was created in. |

The compliance policy is a separate file: [Compliance policy file](policy-file.md).
