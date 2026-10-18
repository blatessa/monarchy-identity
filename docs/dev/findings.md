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
- `su` uses `pam_unix` directly, so directory users can't `su`. The `polkit-1` PAM service exists, but as a vendor file in
  `/usr/lib/pam.d/` (so `ls /etc/pam.d` misses it).
- Omarchy enables autologin on encrypted disks by design (the passphrase is the login).

## PAM / sssd (the lockout class)
- With `pam_sss.so` missing, an `account ... default=bad` rule failed EVERY login (local, root, even sshd) and bricked
  the VM. Rules are now `-account [... user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad]`.
  If the VM is bricked: delete `test/vm/images/client.qcow2` + `OVMF_VARS.fd` and rerun `run.sh`.
- sssd answers for any name its domain has, whatever nsswitch resolves it to. With the module first and no guard, a local
  account sharing a directory user's name was decided by the directory: the owner denied their own account (directory
  user outside the group), or the directory password signing in as the local account, in `wheel`. `pam_localuser`
  skips the module for local names; `useradd` refuses such names once enrolled, so test with accounts made before.
- systemd `start-limit-hit`: >5 sssd (re)starts in 10s leaves sssd FAILED (all directory users locked out). Always `sssd_restart` (reset-failed first).
- `sssctl` prompts "Start SSSD now?" on a TTY when sssd is down and hangs: always `</dev/null` + `timeout`. A hung root
  process holding `/run/monarchy-identity.lock` blocks every later enroll/policy/reassert: find stale processes by PID, never `pkill -f`.
- `pam_faillock` (deny=10) applies to directory users too.
  It counts by name for 15 minutes across every service, so suites run back to back pile up their test users'
  failures until one is locked (`grantors=? res=failed` while `pam_sss` still answers). `deploy.sh --fixtures` clears
  `/run/faillock`; `faillock --user` can't, because it needs the user to exist.
- `pam_sss` refuses password changes initiated by root: test as the user.
- An expired AD password: `pam_sss` auth logs "authentication failure ... 12" but returns success; the 12 comes from
  `pam_acct_mgmt`, and only within the handle that authenticated (a separate account-only check says nothing).
- SDDM never calls `pam_chauthtok`; "new password required" is a failed sign-in. It reads `sddm.conf.d` only at start.
- `foot`'s default Ctrl+Shift+N opens a new terminal with the user's shell, and it reads the user's own `foot.ini`: on the
  change-password screen that was a way past the change. It runs with `--config=/dev/null` and those bindings `none`.
- A session command that exits 1 makes `sddm-helper` exit 1, which SDDM reads as an authentication error: it waits for
  the greeter it already closed and the screen stays black. End a refused session with 0.
- Hyprland 0.56 config is Lua; `hyprctl dispatch exit` is now `hyprctl dispatch 'hl.dsp.exit()'`. It runs in the lab
  VM (`-vga std`, software rendering).
- Hyprland opens an "updated to X" news window on a user's second start, which takes the keyboard: the change-password
  screen sets `ecosystem.no_update_news`. `hyprctl configerrors` (from inside) is how to check a Lua config.
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

## Entra ID / himmelblau (spike, 4.0.6)
- The device joins on the first successful sign-in, with that user's password; no admin credentials, no separate
  join step. It shows in Entra as an Entra-joined Linux device named after the hostname.
- Unjoining locally (`aad-tool cache-clear --full`, prompts Y/N) leaves the device object in Entra, enabled. Deleting
  it needs Graph rights (Cloud Device Administrator or similar).
- NSS answers before anyone signs in, by UPN and by short name (`alice`). `files` stays first, so a local account of
  the same name wins. UIDs/GIDs are murmur3(tenant, object id) into `idmap_range`: the same on every machine.
- `nsswitch.conf` needs `himmelblau` on `shadow:` too, or `pam_unix`'s account check fails with "Authentication
  service cannot retrieve authentication info" after a correct password.
- The daemon creates the home directory itself at session open: `/home/<object-id>` plus a `/home/<upn>` symlink. No
  `pam_mkhomedir`.
- `pam_allow_groups` (group object ids) is enforced in the `account` phase: carol's password is checked, then she's
  refused. `sudo_groups` and `local_groups` exist natively (untested).
- Any failure re-prompts forever inside one `pam_authenticate` (wrong password, MFA enrollment required, offline wrong
  password); it never returns PAM_AUTH_ERR, so faillock never counts. A test driver that always answers the same
  password hammers Entra until it answers AADSTS50196 (request loop) and smart lockout throttles that user for minutes.
  Use a timeout and never loop a wrong password against the tenant. The greeter must handle repeated prompts.
- `ssh` (and other remote services in `password_only_remote_services_deny_list`) refuses password-only sign-in: a user
  without MFA gets AADSTS50072 "needs to enroll for second factor", in the same loop.
- Offline needs `[offline_breakglass] enabled = true`. Without it the password verifier is only cached on the
  first, enrolling sign-in path, so offline gives "No cached password" (the docs suggest single-factor users get offline
  for free; the code doesn't). `enable_sfa_fallback` alone isn't enough. With breakglass on, the first offline attempt
  notices the outage and still succeeds. No knob maps to `--offline-days` (the TTL is breakglass duration, not
  verifier lifetime).
- Upstream's `aad-tool configure-pam` adds unprefixed `auth sufficient pam_himmelblau.so` above `pam_faillock`
  preauth in both `system-auth` and `system-login` (runs twice, bypasses faillock); our core does the PAM edit.
- `enable_hello` defaults to true (Hello PIN enrollment at sign-in); the spike ran with it off.
- Harmless noise: the profile-photo task warns that `/var/lib/AccountsService/icons/` doesn't exist
  (`fetch_profile_picture`).

## Stubs in the fast layer (`test/unit/stubs/`)
The fast layer runs the real CLI with stub commands first on `PATH`. A stub is only as good as the output it copies; these shapes were
captured from the lab VM (samba `net` against the Samba AD, 17 Oct 2026):
- `net ads search -S dc -U Administrator '(&(objectClass=group)(sAMAccountName=oi-laptop-users))' sAMAccountName distinguishedName`
  prints a blank line, `Got 1 replies`, a blank line, then `sAMAccountName: oi-laptop-users` and
  `distinguishedName: CN=oi-laptop-users,CN=Users,DC=corp,DC=test`; no match prints `Got 0 replies` and still exits 0.
- A wrong password (or an admin account that doesn't exist) prints a `gensec_gse_client_prepare_ccache: ... NT_STATUS_LOGON_FAILURE`
  line, then `ads_startup_int: ads_connect_creds: Invalid credentials`, and exits 255. A computer lookup
  (`(sAMAccountName=NAME$)`) has the same shape as the group lookup.
- Failures exit 255 with one `ads_startup_int: ads_connect_creds:` line: an `-S` name that doesn't resolve says `The object was
  not found.`; a DC that is down, an address with no route, and a realm with no DNS SRV records all say `No logon servers are
  currently available to service the logon request.` So `net_explain` checks DNS itself (`getent ahosts`, and `net lookup ldap
  DOMAIN` for the SRV records) to tell "DNS can't find it" from "it doesn't answer".
- `net ads join` failures print `Password for [WG\admin]:` then `Failed to join domain: REASON` (exit 255), e.g. `failed to precreate
  account in ou ou=Gone,...: No such object`, or `Invalid configuration ("workgroup" set to 'X', should be 'CORP')`.
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
- polkit 127 checks prompt passwords in a socket-activated helper unit (`polkit-agent-helper.socket`), not a setuid binary.
  The helper takes the agent's uid from the socket, so `pkexec`'s built-in text agent (setuid root) gets PAM success and then
  `No session for cookie` for everyone (upstream polkit-org/polkit#686, #47). A user-run agent (`pkttyagent`, Omarchy's graphical
  one) works: `test/vm/adminprompt.py`.
  A freshly installed polkit has the socket inactive until reboot, and without it the helper isn't sandboxed: check it's active.
- polkit offers every admin identity (wheel plus the sudo groups) even when the person asking is one of them, in the order the
  rule returns them; picking one is the agent's job. Omarchy's dialog never picks, so Quickshell's `AuthFlow` asks as the first
  (`mIdentities.first()`) without saying whose password it wants: a directory admin was asked for the local admin's (#34). The
  rule now lists an admin who asks first.

## Conventions that came from these
- Anything the CLI sources must also be installed by `packaging/PKGBUILD` (`e2e-package.sh` catches misses).
- Removing the package while enrolled runs `leave` (pre_remove) so PAM edits never outlive the tool.

## Scope
- A self-heal file watcher, an auto-revert timer, a local-fallback precondition, byte-exact backups and a device
  compliance checker were all built and then removed (Oct 2026): they were MDM or undo machinery, not authentication.
  The PAM design already keeps local users working; the rest belongs to whoever deploys this.
