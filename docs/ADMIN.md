# Administrator guide

Audience: someone rolling `monarchy-identity` out to Omarchy laptops. Status: prototype, verified in a VM only
(see [../HANDOFF.md](../HANDOFF.md) for what has and hasn't been tested on a real desktop).

## Giving users documentation
Hand employees the [user guide](user/USER-GUIDE.md) and [quick reference](user/QUICK-REFERENCE.md) (plain language, no admin
knowledge needed; edit them to add your helpdesk contact and your password rules). Tell them what a red login screen
can mean in your environment: it intentionally doesn't say which.

## Install
Build from `packaging/PKGBUILD` (`makepkg -si`) or distribute the `.pkg.tar.zst` through your own repo.
Installing changes nothing until you enrol. `monarchy-identity-shell` (status widget) is optional.

## Before you enrol: three safety rules
1. **A local fallback must exist.** Enrolment refuses unless a local account with a usable password exists
   (the escape hatch if the directory, network or this tool misbehaves). `--allow-no-local-fallback` overrides.
2. **First time on a machine, use the dead-man's switch:** `--confirm-within 10`. If you don't run
   `sudo monarchy-identity confirm` within 10 minutes (after proving a directory user can log in), it leaves the domain
   and restores the previous config by itself.
3. **Test in a VM first.** PAM mistakes lock people out.

## Enrol (Active Directory / Samba AD)
Interactive:

    sudo monarchy-identity enroll sssd --realm CORP.EXAMPLE.COM --admin joinuser \
         --mode groups --groups "laptop-users" --disable-autologin --confirm-within 10
    # prompts for the join account's password on stdin

`--server dc1.corp.example.com` is optional; without it, DCs are found through DNS SRV records.

Login policy (`--mode`, default deny):

| mode       | who can sign in                                   | needs            |
|------------|---------------------------------------------------|------------------|
| `groups`   | members of the listed directory groups            | `--groups a,b`   |
| `assigned` | only the listed users                             | `--users u1,u2`  |
| `any`      | everyone in the directory (explicit opt-in)       | -                |

`--offline-days N` makes cached credentials stop working after N days without reaching the DC (default: never expire).
Local accounts are never governed by this policy, so the break-glass admin keeps working.

**Admin rights:** `--sudo-groups g1,g2` gives those directory groups sudo through a visudo-validated drop-in
(`/etc/sudoers.d/50-monarchy-identity`, 0440; names limited to letters, digits, `.`, `_`, `-`). Off by default; if your MDM
owns privilege, leave it off. Removed by `leave`, repaired by the watcher.

## Automation (MDM, Ansible, cloud-init)
No TTY is needed. Put the join account's password in a root-owned 0600 file (`--password-file`, or env
`OI_ADMIN_PASSWORD_FILE`; group/other-readable files and symlinks are refused):

```yaml
# Ansible sketch
- name: Enrol laptop
  hosts: omarchy_laptops
  become: true
  tasks:
    - name: Install package
      community.general.pacman: { name: monarchy-identity, state: present }
    - name: Stage join credential (from your vault)
      ansible.builtin.copy: { dest: /root/oi.pw, content: "{{ vault_join_password }}\n", mode: "0600", no_log: true }
    - name: Enrol (idempotent enough: skip when already enrolled)
      ansible.builtin.shell: |
        monarchy-identity status --json | grep -q '"enrolled":true' ||
        monarchy-identity enroll sssd --realm CORP.EXAMPLE.COM --admin joinuser \
          --mode groups --groups laptop-users --disable-autologin --password-file /root/oi.pw </dev/null
      args: { executable: /bin/bash }
    - name: Remove credential
      ansible.builtin.file: { path: /root/oi.pw, state: absent }
```
Exit status is 0 on success and non-zero on any failure; a failed enrolment rolls itself back.

## Verify and monitor
`monarchy-identity status --json` is the machine-readable posture (schema: [POSTURE.md](POSTURE.md)): enrolment, login
mode, effective autologin, self-heal state, per-file drift, plus disk-encryption / firewall / Secure Boot / TPM2 / lock
timeout. Feed it to osquery, your MDM's custom-attribute hook, or a cron job. `unknown` means "could not determine".

## Compliance check (for your MDM)
Write `/etc/monarchy-identity/policy.toml` (an annotated example ships in `/usr/share/doc/monarchy-identity/policy.example.toml`),
then run `monarchy-identity check [--json]`. It prints PASS/FAIL per rule and exits **0** compliant, **1** violations,
**2** bad policy (unknown keys, bad values, missing file: a typo never silently weakens a policy). Use it directly as a
custom compliance script in Intune/Ansible/osquery. Rules: enrolled, self-heal, disk encryption, firewall, Secure Boot,
TPM2, no autologin, allowed `wheel` members, maximum screen-lock timeout, required login mode. Values the tool cannot
determine count as failures unless `unknown_is_failure = false`.

## What keeps it correct
- A root-owned systemd path unit (`monarchy-identity-reassert.path`) repairs the PAM, nsswitch and SDDM edits within
  seconds if an update or a person overwrites them. A pacman hook does the same after relevant package upgrades.
- Optional per-user hook for `omarchy update`: run `monarchy-identity install-hooks` as the desktop user.
- Everything the tool changes is backed up to `/var/lib/monarchy-identity/backup` and undone by `leave`.

## Leave
`sudo monarchy-identity leave --admin joinuser --password-file /root/oi.pw` restores the original files and deletes the
computer account. Without `--admin` it leaves the account in the directory and warns (a directory admin must remove it).

## The login screen
Omarchy's stock SDDM theme has no username box (it only logs in the last user). Enrolment therefore selects the
`monarchy-identity` theme: Omarchy's look plus a username line. `--keep-login-theme` opts out (directory users then
can't sign in at the greeter). Autologin is a separate switch: `--disable-autologin`.

## Known limits
- Tested against Samba AD; real Windows AD, FreeIPA and Entra ID/OIDC are untested or not implemented.
- `su` uses pam_unix directly (directory users can't `su`). Sudo is opt-in via `--sudo-groups` (whole-group, ALL commands only).
- **Expired / must-change passwords:** login is refused with "new authentication token required" (tested on every service). SSH and a text login can prompt for a new password, but the **graphical login screen has no change-password dialog**: a user flagged "must change at next logon" must change it first on a TTY (Ctrl+Alt+F3) or over SSH, or an admin should avoid that flag for laptop users.
- GPO-based access control (currently disabled) and smart cards are not handled.
- Not yet verified in a real SDDM/Hyprland session; the lock screen uses the same PAM stack that the tests cover.

## Troubleshooting
- Locked out of a test machine: switch to a TTY (Ctrl+Alt+F3) and log in with the local fallback; run
  `sudo monarchy-identity leave`.
- Enrolment refused: read the message; it names the failed precondition (no local fallback, bad argument, unresolvable group).
- Directory user denied: `journalctl -t sshd -t sddm` and `sudo sssctl user-checks <user>`; check `login_mode` and group membership.
- Brief outage of the DC: users who have signed in before can still log in (cached); never-signed-in users cannot.
