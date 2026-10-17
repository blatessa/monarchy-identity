# Files, units and variables

## Files managed on an enrolled machine

| Path | Change | Restored by `leave` |
|---|---|---|
| `/etc/pam.d/system-auth` | `pam_sss` and `pam_mkhomedir` rules between `# BEGIN/END monarchy-identity` markers | Markers removed; original backed up |
| `/etc/pam.d/omarchy-lock-password` | Same | Same |
| `/etc/nsswitch.conf` | `sss` added to `passwd`, `group`, `shadow` | `sss` removed; original backed up |
| `/etc/sssd/sssd.conf` | Written (mode 0600) | Original restored or removed |
| `/etc/krb5.conf` | Written | Original restored or removed |
| `/etc/samba/smb.conf` | Written | Original restored or removed |
| `/etc/krb5.keytab` | Machine keytab | Original restored or removed |
| `/etc/sddm.conf.d/zz-monarchy-identity.conf` | Autologin override (the default; skipped with `--keep-autologin`) | Removed |
| `/etc/sddm.conf.d/zz-monarchy-identity-theme.conf` | Selects the `monarchy-identity` theme | Removed |
| `/etc/sudoers.d/50-monarchy-identity` | Group sudo rules (`--sudo-groups`), mode 0440 | Removed |
| `/etc/monarchy-identity/config.toml` | [Configuration](config-file.md) | Reset to `provider = "local"` |

Originals are saved once to `/var/lib/monarchy-identity/backup/` (path with `/` replaced by `_`; `.absent` marks a
file that did not exist). `leave` also clears `/var/lib/sss/db` and `/var/lib/sss/mc`.

## Files installed by the package

| Path | Purpose |
|---|---|
| `/usr/bin/monarchy-identity` | CLI |
| `/usr/share/monarchy-identity/providers/` | Provider scripts |
| `/usr/share/monarchy-identity/lib/` | `common.sh`, `posture.sh`, `pamedit.py`, `check.py` |
| `/usr/share/monarchy-identity/hooks/` | `reassert.sh` and the Omarchy post-update hook |
| `/usr/share/libalpm/hooks/monarchy-identity.hook` | pacman hook |
| `/usr/lib/systemd/system/monarchy-identity-reassert.{path,service}` | Self-heal units |
| `/usr/share/sddm/themes/monarchy-identity/` | Login theme (`Main.qml`, `metadata.desktop`, `theme.conf`, symlinks to Omarchy's images) |
| `/etc/monarchy-identity/config.toml` | Default configuration |
| `/usr/share/doc/monarchy-identity/` | Documentation sources and `policy.example.toml` |
| `/usr/share/monarchy-identity/shell-plugin/` | Widget (package `monarchy-identity-shell`) |

## Systemd units

| Unit | Source | Purpose |
|---|---|---|
| `monarchy-identity-reassert.path` | package | Triggers the service when a managed file changes. Enabled by `enroll`, disabled first by `leave`. |
| `monarchy-identity-reassert.service` | package | Runs `monarchy-identity reassert` once. |
| `monarchy-identity-revert.timer` / `.service` | transient, created by the auto-revert | Runs `leave` after the delay. Stopped by `confirm`. |

## Environment variables

| Variable | Used by | Meaning |
|---|---|---|
| `OI_ADMIN_PASSWORD_FILE` | `enroll`, `leave` | Default for `--password-file`. |
| `OI_SUDO` | Omarchy hook | Command used to gain root (default `sudo -n`). |
| `MONARCHY_IDENTITY_POLICY` | `check` | Policy file path. |

These exist to redirect paths for tests and are not part of the supported interface:
`MONARCHY_IDENTITY_ROOT`, `_CONF`, `_STATE`, `_ETC`, `_SDDM_CONF_D`, `_SDDM_THEMES`, `_SUDOERS`, `_LOCK` (all
prefixed `MONARCHY_IDENTITY`).

## Exit codes

| Command | 0 | 1 | 2 |
|---|---|---|---|
| `enroll`, `leave`, `policy`, `reassert`, `confirm`, hooks, widget | success | failure | |
| `check` | compliant | violations | bad policy or input |
| `status`, `providers` | success | | |

## Logging

Messages go to stderr and to the journal with tag `monarchy-identity`: `journalctl -t monarchy-identity`. sssd keeps
its own logs under `/var/log/sssd/`. The pacman and Omarchy hooks log with the same tag, prefixed `reassert:`.
