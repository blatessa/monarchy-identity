# Review: idiomatic Omarchy, and fit for an organisation

Review of monarchy-identity on 2026-10-16, against (1) how Omarchy does things and (2) what an administrator
deploying it across a fleet needs. Method: read Omarchy's own scripts (`omarchy-plugin-*`, hooks, migrations,
installers, SDDM theme), then attack the risky parts in the test VM. Items marked **fixed** have regression tests.

## 1. Idiomatic Omarchy

| Finding | Status |
|---|---|
| Omarchy only discovers shell plugins in `~/.config/omarchy/plugins/<id>/` (and its own first-party dir). The package installed the widget to `/usr/share/...`, where Omarchy never looks. | **fixed**: `install-widget` copies it into the user's plugin dir, validated with `omarchy plugin validate` (the shell's own manifest rules), optional `--enable` |
| `omarchy plugin add <git-url>` expects `manifest.json` at the repo root, so a widget inside a monorepo can't be installed that way. | open: publish the widget as its own repo when the suite has several components |
| Per-user hooks should go through `omarchy hook install`. | **fixed**: `install-hooks` uses it when `omarchy` is present (falls back to a plain copy) |
| `omarchy-hook` runs as the invoking *user*, from the user's own `~/.config`; `omarchy update` keeps sudo alive. A user can delete their own hook. | handled: hook uses `sudo -n`; the root-owned path unit is the tamper-resistant mechanism |
| Omarchy's migrations/installers edit `system-auth` by `sed` on specific lines (faillock) and own `sddm`/`nsswitch` files. | compatible: our edits are marker-wrapped insertions that those `sed` patterns don't touch; the path unit repairs anything overwritten |
| The lock screen uses its own PAM service `omarchy-lock-password` (not package-owned). | handled (edited and tested) |
| **Omarchy's SDDM theme has no username field** (logs in `lastUser` only). | **fixed**: `monarchy-identity` theme; tested in a real greeter |
| Omarchy enables autologin on encrypted disks by design (the passphrase is the login). | documented; `--disable-autologin`, `check`'s `forbid_autologin` |
| Omarchy migrations carefully leave admin-written files alone and judge by content. | followed: unique file names, markers, idempotent writes |
| Omarchy's CLI is `omarchy <group> <action>` via `omarchy-*` binaries with `# omarchy:` metadata. | open: the Monarchy suite should get the same dispatcher (`monarchy identity ...`) once it has a second component; `monarchy-identity` already uses subcommands with `--help` |
| Omarchy has no `polkit-1` PAM service on this install (falls to `other`); `su` bypasses `system-auth`. | open (see TODO) |

## 2. Organisations

| Finding | Status |
|---|---|
| **A missing `pam_sss.so` or dead sssd could lock out everyone**, local users and root included, even over SSH (the account rule used `default=bad`). Reproduced: it bricked the test VM. | **fixed**: `-`-prefixed rules, `module_unknown`/`authinfo_unavail` ignored; `e2e-resilience.sh` |
| Removing the package left PAM edits pointing at modules Omarchy's orphan cleanup may later delete. | **fixed**: `pre_remove` scriptlet runs `leave` |
| `enroll` silently took over an existing computer account (resetting its password, breaking another laptop). | **fixed**: refused unless `--replace-computer-account`; rollback never deletes an account it didn't create |
| Generic (`omarchy`, `archlinux`) or >15-character hostnames collide across a fleet. | **fixed**: refused with guidance; `--computer-name` override |
| No way to place computers in an OU. | **fixed**: `--ou` (DN validated and converted) |
| Changing who may sign in required leaving and re-joining with directory credentials. | **fixed**: `policy set/show` (no re-join, auto-restore on failure) |
| Not idempotent for MDM/Ansible. | **fixed**: `enroll --if-needed` converges policy; password via file |
| Rapid restarts pushed sssd into systemd's `start-limit-hit` (sssd down for everyone until `reset-failed`). | **fixed**: `sssd_restart` helper; 16-change stress test |
| `wait` helper could hang forever on an interactive `sssctl` prompt. | **fixed**: non-interactive, time-boxed |
| Kerberos fails on clock skew. | **fixed**: `time_sync` posture field + `require_time_sync` rule + docs |
| Admins had no deployment guidance (OU, delegated join account, repo, autologin). | **fixed**: rewritten [ADMIN.md](ADMIN.md) |
| `/etc/monarchy-identity/config.toml` mixes admin intent and enrolment state. | open: consider splitting into config and state |
| No fleet-level view (inventory, central policy distribution, signed policies). | open: Monarchy suite scope |
| Only Samba AD is tested; real Windows AD (LDAP signing/channel binding, GPO) is not. | open: highest-value next test target |
| The password-expired flow can't complete on the graphical login screen. | documented; open: add a change-password step to the theme |
| Group name constraints (`--sudo-groups` letters/digits/`._-` only). | documented |
