# Status output

`monarchy-identity status --json` prints one JSON object for scripts and other tools. Anyone can run it.

```json
{
  "schema": 2,
  "enrolled": true,
  "provider": "ad",
  "login_mode": "groups",
  "autologin": false,
  "login_theme": "monarchy-identity",
  "username_field": true,
  "details": {
    "sssd_active": "true",
    "nss_sss": "true",
    "pam_system_auth": "true",
    "pam_omarchy_lock_password": "true",
    "domain_joined": "true"
  }
}
```

| Field | Meaning |
|---|---|
| `schema` | Format version. New fields can be added without changing it; removing or changing one bumps it. |
| `enrolled` | The laptop is connected to a directory. |
| `provider` | The [provider](../providers/index.md) in use, such as `ad`, or `local` when not enrolled. |
| `login_mode` | Who may sign in: `groups`, `assigned` (listed users), `any`, or `none` when not enrolled. |
| `autologin` | Omarchy signs a user in automatically at boot. |
| `login_theme` | The login screen theme in use. |
| `username_field` | The login screen has a username box, so directory users can sign in there. |
| `details` | Provider health checks, each `"true"`, `"false"` or `"unknown"`. Empty when not enrolled. |

Each provider documents its `details` keys on its page, for example
[Active Directory](../providers/ad.md#status-details).

A `"false"` while `enrolled` is true means something overwrote the configuration; `sudo monarchy-identity reassert`
fixes it.

```bash
monarchy-identity status --json | jq -e '.enrolled'                      # exit 0 if enrolled
monarchy-identity status --json | jq -r '.details | to_entries[] | select(.value=="false") | .key'
```
