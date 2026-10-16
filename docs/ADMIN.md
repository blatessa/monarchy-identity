# Administrator guide

Audience: someone rolling `omarchy-identity` out to Omarchy laptops. Status: prototype, verified in a VM only
(see [../HANDOFF.md](../HANDOFF.md) for what has and hasn't been tested on a real desktop).

## Install
Build from `packaging/PKGBUILD` (`makepkg -si`) or distribute the `.pkg.tar.zst` through your own repo.
Installing changes nothing until you enrol. `omarchy-identity-shell` (status widget) is optional.

## Before you enrol: three safety rules
1. **A local fallback must exist.** Enrolment refuses unless a local account with a usable password exists
   (the escape hatch if the directory, network or this tool misbehaves). `--allow-no-local-fallback` overrides.
2. **First time on a machine, use the dead-man's switch:** `--confirm-within 10`. If you don't run
   `sudo omarchy-identity confirm` within 10 minutes (after proving a directory user can log in), it leaves the domain
   and restores the previous config by itself.
3. **Test in a VM first.** PAM mistakes lock people out.

## Enrol (Active Directory / Samba AD)
Interactive:

    sudo omarchy-identity enroll sssd --realm CORP.EXAMPLE.COM --admin joinuser \
         --mode groups --groups "laptop-users" --disable-autologin --confirm-within 10
    # prompts for the join account's password on stdin

`--server dc1.corp.example.com` is optional; without it, DCs are found through DNS SRV records.

Login policy (`--mode`, default deny):

| mode       | who can sign in                                   | needs            |
|------------|---------------------------------------------------|------------------|
| `groups`   | members of the listed directory groups            | `--groups a,b`   |
| `assigned` | only the listed users                             | `--users u1,u2`  |
| `any`      | everyone in the directory (explicit opt-in)       | -                |

Local accounts are never governed by this policy, so the break-glass admin keeps working.

**Admin rights:** `--sudo-groups g1,g2` gives those directory groups sudo through a visudo-validated drop-in
(`/etc/sudoers.d/50-omarchy-identity`, 0440; names limited to letters, digits, `.`, `_`, `-`). Off by default; if your MDM
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
      community.general.pacman: { name: omarchy-identity, state: present }
    - name: Stage join credential (from your vault)
      ansible.builtin.copy: { dest: /root/oi.pw, content: "{{ vault_join_password }}\n", mode: "0600", no_log: true }
    - name: Enrol (idempotent enough: skip when already enrolled)
      ansible.builtin.shell: |
        omarchy-identity status --json | grep -q '"enrolled":true' ||
        omarchy-identity enroll sssd --realm CORP.EXAMPLE.COM --admin joinuser \
          --mode groups --groups laptop-users --disable-autologin --password-file /root/oi.pw </dev/null
      args: { executable: /bin/bash }
    - name: Remove credential
      ansible.builtin.file: { path: /root/oi.pw, state: absent }
```
Exit status is 0 on success and non-zero on any failure; a failed enrolment rolls itself back.

## Verify and monitor
`omarchy-identity status --json` is the machine-readable posture (schema: [POSTURE.md](POSTURE.md)): enrolment, login
mode, effective autologin, self-heal state, per-file drift, plus disk-encryption / firewall / Secure Boot / TPM2 / lock
timeout. Feed it to osquery, your MDM's custom-attribute hook, or a cron job. `unknown` means "could not determine".

## What keeps it correct
- A root-owned systemd path unit (`omarchy-identity-reassert.path`) repairs the PAM, nsswitch and SDDM edits within
  seconds if an update or a person overwrites them. A pacman hook does the same after relevant package upgrades.
- Optional per-user hook for `omarchy update`: run `omarchy-identity install-hooks` as the desktop user.
- Everything the tool changes is backed up to `/var/lib/omarchy-identity/backup` and undone by `leave`.

## Leave
`sudo omarchy-identity leave --admin joinuser --password-file /root/oi.pw` restores the original files and deletes the
computer account. Without `--admin` it leaves the account in the directory and warns (a directory admin must remove it).

## The login screen
Omarchy's stock SDDM theme has no username box (it only logs in the last user). Enrolment therefore selects the
`omarchy-identity` theme: Omarchy's look plus a username line. `--keep-login-theme` opts out (directory users then
can't sign in at the greeter). Autologin is a separate switch: `--disable-autologin`.

## Known limits
- Tested against Samba AD; real Windows AD, FreeIPA and Entra ID/OIDC are untested or not implemented.
- `su` uses pam_unix directly (directory users can't `su`). Sudo is opt-in via `--sudo-groups` (whole-group, ALL commands only).
- Password-expiry-at-login prompts, GPO-based access control (currently disabled) and smart cards are not handled.
- Not yet verified in a real SDDM/Hyprland session; the lock screen uses the same PAM stack that the tests cover.

## Troubleshooting
- Locked out of a test machine: switch to a TTY (Ctrl+Alt+F3) and log in with the local fallback; run
  `sudo omarchy-identity leave`.
- Enrolment refused: read the message; it names the failed precondition (no local fallback, bad argument, unresolvable group).
- Directory user denied: `journalctl -t sshd -t sddm` and `sudo sssctl user-checks <user>`; check `login_mode` and group membership.
- Brief outage of the DC: users who have signed in before can still log in (cached); never-signed-in users cannot.
