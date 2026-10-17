# Findings

Non-obvious behaviour learned the hard way, kept so it is not rediscovered. Add to this page when you learn
something.

## Omarchy
- The lock screen uses its own PAM service `/etc/pam.d/omarchy-lock-password` (not package-owned). It must be edited too.
- Omarchy ships `etc-overrides/nsswitch.conf`; updates may reset `sss`. Reassert re-adds it.
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
- `net ads leave` needs admin creds + `-S` to delete the computer account. The auto-revert timer's `leave` has no
  credentials, so it leaves the account behind; re-enrolling needs `--replace-computer-account`.
- `enroll` rolls back through an EXIT trap with an `enrolled_ok` flag (an ERR trap never fires because `die` calls `exit`).

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

## Conventions that came from these
- Anything the CLI sources must also be installed by `packaging/PKGBUILD` (`e2e-package.sh` catches misses; `posture.sh` was missed once).
- Removing the package while enrolled runs `leave` (pre_remove) so PAM edits never outlive the tool.
