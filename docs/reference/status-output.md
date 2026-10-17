# Status output

`monarchy-identity status --json` prints one JSON object for scripts and other tools. Anyone can run it.

```json
{
  "schema": 2,
  "enrolled": true,
  "provider": "sssd",
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
| `enrolled` | The laptop is joined to a directory. |
| `provider` | `sssd` (Active Directory), or `local` when not enrolled. |
| `login_mode` | Who may sign in: `groups`, `assigned` (listed users), `any`, or `none` when not enrolled. |
| `autologin` | Omarchy signs a user in automatically at boot. |
| `login_theme` | The login screen theme in use. |
| `username_field` | The login screen has a username box, so directory users can sign in there. |
| `details` | Provider health, as `"true"`, `"false"` or `"unknown"`. Empty when not enrolled. |

For the Active Directory provider, `details` holds:

| Key | `"true"` means |
|---|---|
| `sssd_active` | The directory service is running. |
| `nss_sss` | The laptop looks up users in the directory. |
| `pam_system_auth` | Sign-in (login screen, terminal, `ssh`, `sudo`) uses the directory. |
| `pam_omarchy_lock_password` | The lock screen uses the directory. |
| `domain_joined` | The laptop's computer account works. Only known when run as root. |

A `"false"` while `enrolled` is true means something overwrote the configuration; `sudo monarchy-identity reassert`
fixes it.

```bash
monarchy-identity status --json | jq -e '.enrolled'                      # exit 0 if enrolled
monarchy-identity status --json | jq -r '.details | to_entries[] | select(.value=="false") | .key'
```
