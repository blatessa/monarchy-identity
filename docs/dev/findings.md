# Findings

Non-obvious behaviour learned the hard way, kept so it is not rediscovered. Add to this page when you learn
something.

## Omarchy
- The lock screen uses its own PAM service `/etc/pam.d/omarchy-lock-password` (not package-owned). It must be edited too.
- Omarchy ships `etc-overrides/nsswitch.conf`; updates may reset `sss`. The pacman hook's reassert re-adds it.
- SDDM drop-ins merge in C-locale filename order, last wins. Omarchy's `autologin.conf` sorts after `99-*`, so ours is `zz-*`.
- Omarchy's SDDM greeter runs inside Hyprland; the VM uses SDDM's X11 greeter (same theme QML, daemon, PAM).
- `omarchy-hook` runs as the invoking USER from `~/.config/omarchy/hooks`; `omarchy update` keeps sudo alive, so hooks use `sudo -n`.
- Plain pacman upgrades keep modified `backup=` files (`.pacnew`); real drift comes from migrations and manual edits.
- Omarchy has no `polkit-1` PAM service (falls to `other`); `su` uses `pam_unix` directly, so directory users can't `su`.
- Omarchy enables autologin on encrypted disks by design (the passphrase is the login).

## PAM / sssd (the lockout class)
- With `pam_sss.so` missing, an `account ... default=bad` rule failed EVERY login (local, root, even sshd) and bricked
  the VM. Rules are now `-account [... user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad]`.
  If the VM is bricked: delete `test/vm/images/client.qcow2` + `OVMF_VARS.fd` and rerun `run.sh`.
- systemd `start-limit-hit`: >5 sssd (re)starts in 10s leaves sssd FAILED (all directory users locked out). Always `sssd_restart` (reset-failed first).
- `sssctl` prompts "Start SSSD now?" on a TTY when sssd is down and hangs: always `</dev/null` + `timeout`. A hung root
  process holding `/run/monarchy-identity.lock` blocks every later enroll/policy/reassert: find stale processes by PID, never `pkill -f`.
- `pam_faillock` (deny=10) applies to directory users too.
- `pam_sss` refuses password changes initiated by root: test as the user.
- `lib/pamedit.py` computes skip counts from the file so it is safe next to Omarchy's `pam_systemd_home` lines; `remove` restores byte-identical.

## Samba / Kerberos / AD
- sssd, samba, krb5 are in Arch `extra`; adcli and oddjob are AUR-only (not used).
- DC discovery needs UDP 389 (CLDAP). Samba commands need `-S <server>` when there is no DNS (the lab).
- Fresh computer account quirk: after the first `net ads join`, sssd gets "Preauthentication failed" although `kinit -k`
  works; a second join fixes it, so enroll joins twice. Cause unknown (only `pwdLastSet` differs). Keytab must be built
  with `net ads keytab create -S srv -U admin` (NOT `-P`) after `rm -f /etc/krb5.keytab`.
- `net ads leave` needs admin creds + `-S` to delete the computer account; without them the account stays behind and
  re-enrolling that name needs `--replace-computer-account`.
- `net ads search -U admin` checks the password, DC reachability and group names in one go, before anything is joined.
  An empty result still exits 0 ("Got 0 replies"): match the attribute line, not the exit code.

## Stubs in the fast layer (`test/unit/stubs/`)
The fast layer runs the real CLI with stub commands first on `PATH`. A stub is only as good as the output it copies; these shapes were
captured from the lab VM (samba `net` against the Samba AD, 17 Oct 2026):
- `net ads search -S dc -U Administrator '(&(objectClass=group)(sAMAccountName=oi-laptop-users))' sAMAccountName distinguishedName`
  prints a blank line, `Got 1 replies`, a blank line, then `sAMAccountName: oi-laptop-users` and
  `distinguishedName: CN=oi-laptop-users,CN=Users,DC=corp,DC=test`; no match prints `Got 0 replies` and still exits 0.
- A wrong password prints `ads_startup_int: ads_connect_creds: Invalid credentials` and exits 255. A computer lookup
  (`(sAMAccountName=NAME$)`) has the same shape as the group lookup.
- Not observed, so assumed: the output when the DC is unreachable. The stub only fails with exit 255, which is all
  `directory_missing_groups` looks at (any non-zero exit); `e2e-offline` checks the real refusal.
- `systemctl is-active` must exit non-zero when the unit is down. A stub that ends in `exit 0` after the `case` made
  every provider status check report healthy.
- The fast layer runs as fake root with `unshare -r`. On Ubuntu runners, AppArmor blocks that unless
  `kernel.apparmor_restrict_unprivileged_userns=0` (CI sets it). Files created there are owned by uid 0, so the
  password-file ownership check behaves as it does for real root.

## Test lab
- `deploy.sh` WITHOUT `--fixtures` keeps the current PAM files; WITH it resets `/etc/pam.d` to stock Omarchy (undoes edits).
- `run.sh`'s cloud-init seed server (python http.server :8000) can be a STALE process from a renamed directory: the VM
  silently provisions with defaults. `run.sh` now replaces any listener on :8000.
- `loginctl terminate-session` makes SDDM treat the helper as crashed and NOT restart the greeter: end test sessions by letting the script exit. SDDM logs failed logins with `user ""`.
- `samba-tool group addmembers a,b` rejects the whole call if any is already a member: seed per member.
- Files created by one user in a shared sticky dir aren't writable by another (`fs.protected_regular`): use a world-writable non-sticky dir.
- `hostnamectl --transient` is ignored when a static hostname exists: simulate hostnames with `sysctl kernel.hostname=`.
- When patching scripts with python `s.index(...)`, make sure you match the intended occurrence.
- The VM's SSH private key was once committed (anchored `.gitignore` bug) and purged from history. Never commit `test/vm/images`, `test/vm/keys`.
- The NetBIOS domain name is not the realm's first label (`badcaptcha.net` can be `BAD`). `smb.conf` `workgroup` must be the
  NetBIOS name or `net ads join` fails, and the script hides its output. `enroll` asks the DC (`net ads lookup`, `Pre-Win2k Domain:`).
  The lab's `corp.test`/`CORP` hid this; found on a real Windows Server 2025 DC.
- Omarchy's theme switch writes browser policy as root and grants that to `%wheel` only. A directory user is in no local group, so
  every login showed a graphical password prompt (real hardware, Oct 2026). `enroll` mirrors that one narrow rule for the sign-in
  groups (`51-monarchy-identity-theme`); making them wheel would hand out full sudo. `su`/`su-l` on Arch use `pam_unix` directly, so
  `su - user` can never test directory sign-in: use a console login or the greeter.
- Admin prompts (polkit) take admin identities from rules, and Omarchy's default is `unix-group:wheel`; directory groups can't join wheel,
  so a directory admin could `sudo` but not answer one. Polkit stops at the first rule that answers, so `49-monarchy-identity.rules` sorts
  before `50-default` and names wheel too (else it would replace the local admins). The `polkit-1` PAM service is a vendor file in
  `/usr/lib/pam.d/` that includes `system-auth`, so directory passwords already work there (not in `/etc/pam.d`, which is why `ls` misses it).

## Conventions that came from these
- Anything the CLI sources must also be installed by `packaging/PKGBUILD` (`e2e-package.sh` catches misses).
- Removing the package while enrolled runs `leave` (pre_remove) so PAM edits never outlive the tool.

## Scope
- A self-heal file watcher, an auto-revert timer, a local-fallback precondition, byte-exact backups and a device
  compliance checker were all built and then removed (Oct 2026): they were MDM or undo machinery, not authentication.
  The PAM design already keeps local users working; the rest belongs to whoever deploys this.
