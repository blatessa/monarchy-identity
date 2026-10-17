# What enrollment changes

`monarchy-identity enroll sssd` performs these steps in order. Everything before step 4 happens without touching the
machine's authentication.

1. Validate every argument (realm, server, admin, group and user lists, OU, confirm minutes) before anything
   changes.
2. Check the hostname and pick the computer account name (see [Rollout planning](../guides/rollout-planning.md)).
3. Check that a local account with a usable password exists; read the join password.
4. Back up the original of each managed file to `/var/lib/monarchy-identity/backup`.
5. Write `/etc/krb5.conf` and `/etc/samba/smb.conf`.
6. Search the directory for an existing computer account of that name. If there is one, stop unless
   `--replace-computer-account` was given.
7. `net ads join` (twice, see [Findings](../dev/findings.md)), then build `/etc/krb5.keytab` and verify it with
   `kinit -k`.
8. Write `/etc/sssd/sssd.conf`, enable and start sssd, wait for it to report online.
9. Add `sss` to `passwd`, `group` and `shadow` in `/etc/nsswitch.conf`.
10. In `groups` mode, require the first listed group to resolve through sssd. If it does not, stop with an error
    and do not touch PAM.
11. Edit the PAM stacks with `lib/pamedit.py`.
12. Optional pieces: SDDM autologin override, sudoers drop-in, SDDM theme.
13. Record state in `/etc/monarchy-identity/config.toml`, enable the self-heal path unit, and schedule the
    auto-revert if `--confirm-within` was given.

If anything fails after step 4, the machine is restored through the same code path as `leave`, and a computer account
created by this run is deleted. An account that already existed is never deleted by the rollback.

## The PAM edit

`lib/pamedit.py` inserts blocks delimited by `# BEGIN monarchy-identity` and `# END monarchy-identity` into
`/etc/pam.d/system-auth` and `/etc/pam.d/omarchy-lock-password`:

```text
-auth      [success=N default=ignore]  pam_sss.so forward_pass
-account   [success=N user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad]  pam_sss.so
-password  [success=N default=ignore]  pam_sss.so
session    required   pam_mkhomedir.so umask=0077
-session   optional   pam_sss.so
```

`N` is computed from the file so that a successful `pam_sss` result skips the `pam_unix`/`pam_faillock` rules that
follow, including next to Omarchy's `pam_systemd_home` lines. The leading `-` makes each rule silent when
`pam_sss.so` cannot be loaded, and the account rule treats `user_unknown`, `authinfo_unavail` and `module_unknown` as
"ignore", so a missing module or a stopped sssd cannot fail a local login. Only a definite answer from `pam_sss`
(denied, expired, new token required) fails a login. Home directories are created on first sign-in with mode 0700.

`remove` deletes exactly the marked blocks.

## Machine state touched

The full list is in [Files, units and variables](../reference/files.md). `leave` restores the backed-up files and
removes the drop-ins.
