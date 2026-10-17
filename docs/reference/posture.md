# Posture report

`monarchy-identity status --json` prints one JSON object on one line. It is read-only and works unprivileged.
Anything that cannot be determined is the string `"unknown"`, never a guess and never an error. Additive changes
keep `schema`; breaking changes bump it.

```json
{
  "schema": 1,
  "enrolled": true,
  "provider": "sssd",
  "login_mode": "groups",
  "autologin": false,
  "revert_pending": false,
  "self_heal": true,
  "wheel_members": "root,admin",
  "login_theme": "monarchy-identity",
  "username_field": true,
  "details": {
    "sssd_active": "true",
    "nss_sss": "true",
    "pam_system_auth": "true",
    "pam_omarchy_lock_password": "true",
    "domain_joined": "true"
  },
  "device": { "hostname": "laptop-0042", "os": "Arch Linux", "omarchy": "unknown", "kernel": "7.2.9-arch1-1" },
  "compliance": {
    "disk_encryption": "true",
    "firewall": "active",
    "secure_boot": "enabled",
    "tpm2": "present",
    "screen_lock_seconds": "300",
    "time_sync": "true"
  }
}
```

## Top level

| Field | Type | Meaning |
|---|---|---|
| `schema` | number | Schema version, currently `1`. |
| `enrolled` | boolean | The configured provider is not `local`. |
| `provider` | string | `sssd` or `local`. |
| `login_mode` | string | `groups`, `assigned`, `any`, or `none`. |
| `autologin` | boolean | Effective SDDM autologin: the merged `sddm.conf.d` result, last file wins. |
| `revert_pending` | boolean | An unconfirmed `--confirm-within` timer is armed. |
| `self_heal` | boolean | `monarchy-identity-reassert.path` is active. |
| `wheel_members` | string | Comma-separated members of the `wheel` group. |
| `login_theme` | string | Effective SDDM theme name. |
| `username_field` | boolean | The effective theme is `monarchy-identity`. |

## `details` (provider-specific)

Printed from the provider's `status` script as `key=value`. Empty (`{}`) when not enrolled. For `sssd`:

| Key | Meaning |
|---|---|
| `sssd_active` | sssd is running. |
| `nss_sss` | `sss` appears in the `passwd` line of `/etc/nsswitch.conf`. |
| `pam_system_auth`, `pam_omarchy_lock_password` | The marked block is present in that PAM file. |
| `domain_joined` | `net ads testjoin` succeeds. `unknown` when not root. |

**Drift:** any `pam_*` or `nss_sss` equal to `"false"` while `enrolled` is true.

## `device`

| Field | Source |
|---|---|
| `hostname` | `uname -n` |
| `os` | `PRETTY_NAME` from `/etc/os-release` |
| `omarchy` | `omarchy-version`, or `unknown` |
| `kernel` | `uname -r` |

## `compliance`

| Field | Values | How it is determined |
|---|---|---|
| `disk_encryption` | `true`, `false`, `unknown` | The root filesystem's device stack contains a `crypt` device (LUKS, including LVM on LUKS). |
| `firewall` | `active`, `inactive`, `unknown` | An installed `ufw`, `firewalld` or `nftables` service is active. `unknown` if none is installed. |
| `secure_boot` | `enabled`, `disabled`, `no-efi`, `unknown` | The `SecureBoot` EFI variable. |
| `tpm2` | `present`, `absent` | `/dev/tpmrm0` exists. |
| `screen_lock_seconds` | number or `unknown` | `idle.lock` in the invoking user's `~/.config/omarchy/shell.json`. |
| `time_sync` | `true`, `false`, `unknown` | `timedatectl` reports `NTPSynchronized`. |

Probes live in `lib/posture.sh`.

## Example queries

```bash
monarchy-identity status --json | jq -e '.enrolled and .compliance.disk_encryption=="true"'
monarchy-identity status --json | jq -r '.details | to_entries[] | select(.value=="false") | .key'
```
