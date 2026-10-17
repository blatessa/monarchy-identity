# Architecture

monarchy-identity is provider-agnostic: a core CLI dispatches to directory-specific providers. The decisions
here are settled; change them deliberately.

## Scope and security model
- This package owns: directory enrolment, login policy, drift repair, posture reporting.
- Privilege removal (wheel), sudo rules and boot hardening belong to the org's MDM/config management. An optional
  `managed` profile (off by default) is planned for orgs with no MDM.
- Enforcement lives in root-owned `/etc`. The shell widget is cosmetic, never a security boundary.
- Default is deny. Local break-glass accounts work in every mode.
- `monarchy-identity status --json` ([posture report](../reference/posture.md)) is the integration point for MDM/osquery/Ansible.
- No AUR dependencies: join with samba `net ads join`, home dirs via `pam_mkhomedir` (adcli/oddjob are AUR-only).
- Never edit `/usr/share/omarchy/` (package-owned). Use `/etc` drop-ins and markers.

## Packages
- `monarchy-identity` (`packaging/PKGBUILD`): CLI, providers, hooks, login theme, systemd units. Root-installed;
  works without the Omarchy shell (SDDM, SSH, headless enrolment). Installing does nothing until you enrol.
- `monarchy-identity-shell`: optional Quickshell bar widget. Depends on the CLI; the CLI never depends on it.

## Layers
1. **Providers** (`providers/<name>/{detect,enroll,unenroll,reassert,status}` + `lib.sh`): the directory-specific
   part. `status` prints `key=value` lines. First provider: `sssd` (AD/Samba AD). Planned: FreeIPA, OIDC.
2. **Core CLI** (`bin/monarchy-identity`): `status | enroll | leave | policy | check | confirm | reassert |
   install-hooks | install-widget | providers`. Applies a provider, writes root-owned drop-ins, backs up originals to
   `/var/lib/monarchy-identity/backup`, rolls back on failure.
3. **Shell widget** (`shell-plugin/`): display only.

## Provider contract
Providers source `lib/common.sh`, use `$OI_ROOT` (set by the CLI), and write state to
`/etc/monarchy-identity/config.toml` (flat `key = "value"`). `enroll` must verify the directory works BEFORE touching
PAM and roll back fully on failure. `unenroll` must restore the pre-enrolment state exactly.

## Login policy (`login.mode`)
`groups` (members of listed directory groups), `assigned` (listed users), `any` (whole directory, explicit opt-in).
Local accounts are not governed by it.

## What we touch (all survive `omarchy update`, all self-healed)
| File | Why |
|---|---|
| `/etc/pam.d/system-auth`, `/etc/pam.d/omarchy-lock-password` | `pam_sss` rules via `lib/pamedit.py` (BEGIN/END markers) |
| `/etc/nsswitch.conf` | add `sss` |
| `/etc/sssd/`, `/etc/krb5.conf`, `/etc/samba/smb.conf` | provider config |
| `/etc/sddm.conf.d/zz-monarchy-identity*.conf` | login theme, optional autologin off (must sort AFTER Omarchy's `autologin.conf`) |
| `/etc/sudoers.d/50-monarchy-identity` | optional `--sudo-groups` (visudo-validated) |
| `/etc/monarchy-identity/config.toml`, `policy.toml` | our configuration; compliance policy |

## Drift repair
- `monarchy-identity-reassert.path` (root-owned systemd path unit, enabled by enroll, disabled FIRST by leave; a
  flock serialises with the CLI) re-applies edits within seconds. This is the tamper-resistant mechanism.
- A pacman alpm hook does the same after relevant package upgrades.
- An optional per-user `omarchy update` hook (`install-hooks`) runs as the user with `sudo -n`; users can delete it.

## Login theme
Omarchy's stock SDDM theme has no username box (it logs in `lastUser` only), so enrolment selects
`sddm-theme/monarchy-identity`: Omarchy's look plus a username line (`--keep-login-theme` opts out).
