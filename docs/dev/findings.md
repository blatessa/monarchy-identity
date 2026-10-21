# Findings

Non-obvious behaviour learned the hard way. Add to it when you learn something.

## Omarchy

- The lock screen uses `/etc/pam.d/omarchy-lock-password` (not package-owned); it's edited too.
- Omarchy ships `etc-overrides/nsswitch.conf`; updates may drop `sss`. The pacman hook's `reassert` re-adds it.
- SDDM drop-ins merge in C-locale filename order, last wins. Omarchy's `autologin.conf` sorts after `99-*`, so ours are `zz-*`.
- Omarchy's greeter runs inside Hyprland; the VM uses SDDM's X11 greeter (same theme QML, daemon, PAM).
- `omarchy-hook` runs as the user from `~/.config/omarchy/hooks`; `omarchy update` keeps sudo alive, so hooks use `sudo -n`.
- Plain pacman upgrades keep modified `backup=` files (`.pacnew`); drift comes from migrations and manual edits.
- `su`/`su-l` use `pam_unix` directly: directory users can't `su`, and `su - user` can't test directory sign-in.
- `polkit-1`'s PAM file is a vendor file in `/usr/lib/pam.d/` (not `/etc/pam.d`); it includes `system-auth`.
- Omarchy enables autologin on encrypted disks (the passphrase is the login).
- A home owned by another UID (left by the previous directory's user of the same name) passes PAM, then SDDM
  can't `chdir` into it and goes straight back to the login screen with no message.
- Omarchy's theme switch writes browser policy as root and grants that to `%wheel` only: directory users got a
  password prompt at every login. `51-monarchy-identity-theme` grants that one command to the sign-in groups.
- Hyprland 0.56 config is Lua; `hyprctl dispatch exit` is `hyprctl dispatch 'hl.dsp.exit()'`; `hyprctl configerrors`
  checks it from inside. Hyprland opens an "updated to X" window on a user's second start that takes the keyboard:
  the change-password screen sets `ecosystem.no_update_news`.
- `foot`'s Ctrl+Shift+N opens a terminal with the user's shell and reads the user's `foot.ini`: on the change-password
  screen that bypassed the change. It runs with `--config=/dev/null` and those bindings `none`.

## PAM / sssd

- With `pam_sss.so` missing, `account ... default=bad` failed every login (local, root, sshd). Rules are
  `-account [... user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad]`. Bricked VM: delete
  `test/vm/images/client.qcow2` and `OVMF_VARS.fd`, rerun `run.sh`.
- sssd answers for any name in its domain. Without `pam_localuser`, a local account sharing a directory user's name was
  decided by the directory (owner refused, or the directory password let in with `wheel`). `useradd` refuses such names
  once enrolled, so test with accounts made before.
- More than 5 sssd (re)starts in 10 s: `start-limit-hit`, sssd failed, everyone locked out. Use `sssd_restart`.
- `sssctl` prompts "Start SSSD now?" on a TTY and hangs: always `</dev/null` and `timeout`. A hung root process holding
  `/run/monarchy-identity.lock` blocks later commands: find it by PID, never `pkill -f`.
- `pam_faillock` (deny=10) counts directory users by name for 15 minutes across services: back-to-back suites lock
  test users. `deploy.sh --fixtures` clears `/run/faillock` (`faillock --user` needs the user to exist).
- `pam_sss` refuses password changes initiated by root: test as the user.
- Expired AD password: `pam_sss` auth logs "authentication failure ... 12" but succeeds; the 12 comes from
  `pam_acct_mgmt`, only in the handle that authenticated.
- SDDM never calls `pam_chauthtok`; "new password required" is a failed sign-in. It reads `sddm.conf.d` only at start.
- A session command that exits 1 makes `sddm-helper` exit 1: SDDM waits for a greeter it closed, black screen. Exit 0.
- `lib/pamedit.py` computes skip counts from the file, so it works next to `pam_systemd_home`; `remove` is byte-exact.

## Samba / Kerberos / AD

- sssd, samba, krb5 are in `extra`; adcli and oddjob are AUR-only (not used).
- DC discovery needs UDP 389 (CLDAP). Samba commands need `-S <server>` without DNS (the lab).
- After the first `net ads join` of a fresh computer account, sssd gets "Preauthentication failed" though `kinit -k`
  works; a second join fixes it, so enroll joins twice. Cause unknown. Build the keytab with
  `net ads keytab create -S srv -U admin` (not `-P`) after `rm -f /etc/krb5.keytab`.
- `net ads leave` needs admin credentials and `-S` to delete the computer account.
- `net ads search -U admin` checks the password, reachability and group names at once. An empty result exits 0
  ("Got 0 replies"): match the attribute line.
- The NetBIOS name isn't the realm's first label (`badcaptcha.net` can be `BAD`); `smb.conf` `workgroup` must be it or
  the join fails silently. `enroll` asks the DC (`net ads lookup`, `Pre-Win2k Domain:`). Found on Windows Server 2025.

## Entra ID / himmelblau 4.0.6

Registration and config

- The device registers at the first successful sign-in, with that user's password. It shows as an Entra-joined Linux
  device named after the hostname. `aad-tool cache-clear --full` unjoins locally; the device object stays, enabled.
- The registration (`device_id`) is in `/var/cache/himmelblaud/himmelblau.conf`, not `/etc`: rewriting our config keeps
  it. After an unjoin the next sign-in registers a new device of the same name.
- The package owns `/etc/himmelblau/himmelblau.conf` (`backup`); an edited one became `.pacsave` on removal and stock on
  reinstall. himmelblau reads `himmelblau.conf.d/*.conf` after it (PAM and NSS modules too): ours is a drop-in.
- Graph's device list lags a registration by a minute or more; check `device_id`.
- NSS answers by UPN and short name before anyone signs in. `files` stays first. UIDs/GIDs are murmur3(tenant, object
  id) in `idmap_range`: the same everywhere.
- `shadow:` needs `himmelblau` too, or `pam_unix`'s account check fails after a correct password.
- `pam_allow_groups` (object ids) is enforced in `account`. Unset, every tenant user may sign in (only a warning).
- Groups don't resolve through NSS before the device joins (users do): enroll needs Graph and a client secret.
- Upstream's `aad-tool configure-pam` adds unprefixed `auth sufficient pam_himmelblau.so` above faillock in both
  `system-auth` and `system-login`. The core does the PAM edit instead.
- `himmelblaud` keeps PRTs in systemd's fd store (`FileDescriptorStorePreserve=yes`), surviving `systemctl stop`.
  After an unjoin they don't match the device keys and the daemon answers nothing on the next enroll. `leave` runs
  `systemctl clean --what=fdstore --what=state --what=cache` on both units.
- `enable_hello` defaults to true (PIN enrollment at sign-in); we set it false.

Homes

- By default the daemon makes `/home/<object id>` plus a `/home/<upn>` link, and passwd names the link. `home_alias`
  decides what passwd says: `home_attr = home_alias = cn` gives `/home/alice`.
- Its skeleton copy (`use_etc_skel`, off by default) stops at the first error and never repairs: Omarchy's skeleton
  came out 92 of 10,238 entries (no theme, 124 pending migrations needing sudo). `pam_mkhomedir` copies it all. The
  lab's skeleton is Arch's, so `e2e-entra` adds a deep file and a dangling link.

Sign-in

- Any failure re-prompts inside one `pam_authenticate` (wrong password, MFA enrollment needed, offline wrong password);
  it never returns PAM_AUTH_ERR, so faillock doesn't count. Answering the same password in a loop gets AADSTS50196 and
  smart lockout throttles the user for minutes. Never loop a wrong password against the tenant.
- SDDM 0.21 answers every prompt with the typed password (`Display::slotRequestChanged`): at the login screen that
  loop sends it forever, as the MFA code or after a typo (himmelblau#1882). `lib/login-steps` exists for this.
- MFA (code): asked after the password at the first sign-in on the device; then "Sign-in frequency satisfied for user
  via PRT - skipping MFA" (login screen, lock screen, `sudo`). `sshd` asks every time. Before that first sign-in,
  `pam_acct_mgmt` alone fails for every user. No input to `Code:` ends with `PAM_ABORT`, nothing sent; a wrong code
  is `MFAInvalidCode`, then the loop.
- Before a first completed sign-in, NSS resolves the user by name but not by uid: logind's `CreateSession` fails and no
  session can start. So MFA can't be finished in a screen after the login screen.
- System-preferred MFA sends a push whenever Authenticator push is registered. `mfa_method = PhoneAppOTP` asks for the
  code; the lab sets it in a test-only drop-in.
- `ssh` (`password_only_remote_services_deny_list`) refuses password-only sign-in: AADSTS50072, in the same loop.
- The first sign-in after the network drops returns PAM_ABORT ("Network outage detected"); the next answers from the
  offline cache. Ours retries after an abort (`auth_retry_on_abort`); upstream's `configure-pam` lists the module twice.
- Offline needs `[offline_breakglass] enabled = true`; without it the verifier is only cached on the enrolling sign-in
  ("No cached password"). No setting maps to `--offline-days`.
- After ~30 s idle, a sign-in step twice logged "Network down detected" and the daemon went offline ("NotFound: token
  in AuthSession" for a user with nothing cached). Probably a pooled connection Microsoft closed. Asking again works.
- The module logs to stdout; `pam_exec` hands a script's stdout to the login screen. `lib/login-steps` moves its own
  stdout aside, or people see `PAM_CONV_ERR`.

Passwords

- `passwd` (`pam_sm_chauthtok`) changes a Hello PIN, never the Entra password.
- A password that must be changed (expired, or reset with `forceChangePasswordNextSignIn`) is changed inside
  `pam_authenticate`: after the password, "Update your password", `New password:`, `Confirm password:` (translated:
  `himmelblau.mo`), then sign-in continues with the new one. Under 8 characters is refused locally.
- In released himmelblau that only works at the laptop's first sign-in, for a user without MFA. On a joined laptop
  Entra answers the silent token exchange with AADSTS50058 (or AADSTS50133 if the user had a PRT before the reset) and
  himmelblau reports a refusal. With MFA, the change page is thrown away and the change fails ("Authentication failed").
  Fixes upstream, unreleased: himmelblau#1888, libhimmelblau#109. Until then `lib/login-steps` tells the person to sign
  in at myaccount.microsoft.com first (verified in the lab on 4.0.6). A refused new password shows "Authentication failed"
  instead of Entra's reason until himmelblau#1904.
- An MFA user who signed in minutes before an admin reset can sign in with the reset password, no change, until Entra
  revokes the session.
- A user or password set through Graph isn't accepted by sign-in for a minute or two (refused as a wrong password); the
  change page can answer `AADSTS120016: User not found` for a new user.

himmelblau 4.0.7 (not used)

- The unit now has socket units, `DynamicUser=yes` and `LoadCredentialEncrypted=hsm-pin:...`. Decrypting the credential
  goes through `io.systemd.Credentials`, whose NSS lookup reaches nss_himmelblau, which connects to the socket systemd
  holds for the daemon that isn't running yet: it waits for systemd's 25 s varlink timeout (`ERRNO=110`). Every start
  took ~31 s instead of ~11 s, and some failed. Every NSS lookup on the machine blocks meanwhile (`sudo` too). The
  module's `should_skip_daemon_call` only covers the daemon's own units. Reproduce: 4.0.7, `himmelblau` in nsswitch,
  `systemctl restart himmelblaud`.
- ~6 s of every start is argon2 parameter calibration (both versions).
- Both are himmelblau#1809 (reported on NixOS, open).

## Stubs in the fast layer

Shapes captured from the lab (samba `net` against Samba AD, 17 Oct 2026):

- `net ads search -S dc -U Administrator '(&(objectClass=group)(sAMAccountName=oi-laptop-users))' sAMAccountName
  distinguishedName`: a blank line, `Got 1 replies`, a blank line, `sAMAccountName: oi-laptop-users`,
  `distinguishedName: CN=oi-laptop-users,CN=Users,DC=corp,DC=test`. No match: `Got 0 replies`, exit 0. A computer
  lookup (`(sAMAccountName=NAME$)`) has the same shape.
- Wrong password or unknown admin: a `gensec_gse_client_prepare_ccache: ... NT_STATUS_LOGON_FAILURE` line, then
  `ads_startup_int: ads_connect_creds: Invalid credentials`, exit 255.
- Other failures exit 255 with one `ads_startup_int: ads_connect_creds:` line: an unresolvable `-S` says `The object
  was not found.`; a DC down, no route, or no SRV records all say `No logon servers are currently available to service
  the logon request.` `net_explain` checks DNS itself (`getent ahosts`, `net lookup ldap DOMAIN`).
- `net ads join` failures: `Password for [WG\admin]:` then `Failed to join domain: REASON` (exit 255).
- `systemctl is-active` stubs must exit non-zero when down (one that ended in `exit 0` made every check healthy).
- The fast layer uses `unshare -r`; Ubuntu runners need `kernel.apparmor_restrict_unprivileged_userns=0` (CI sets it).
  Files made there are owned by uid 0, so the password-file ownership check behaves as for real root.

## Lab

- `deploy.sh` without `--fixtures` keeps the VM's PAM files; with it, stock Omarchy PAM/SDDM.
- `run.sh`'s cloud-init seed server (:8000) can be a stale process from a renamed directory: the VM provisions with
  defaults. `run.sh` replaces any listener on :8000.
- `loginctl terminate-session` makes SDDM treat the helper as crashed and not restart the greeter: end test sessions by
  letting the script exit. SDDM logs failed logins with `user ""`.
- `samba-tool group addmembers a,b` rejects the whole call if one is already a member: one member per call.
- Files one user creates in a sticky shared dir aren't writable by another (`fs.protected_regular`).
- `hostnamectl --transient` is ignored with a static hostname: use `sysctl kernel.hostname=`.
- `e2e-offline` moves the VM's clock, so the journal has entries dated in the future and `journalctl --since` mixes
  checks: count himmelblaud steps by cursor (`hb_mark`, `steps`).
- `deploy.sh` used to tar the whole repo, mkdocs `.venv` included: 100 MB per deploy. It ships the runtime dirs only.
- Bash ignores `PS4` from the environment for root: `sudo env PS4=... bash -x` prints no timestamps.
- polkit 127 checks passwords in a socket-activated helper (`polkit-agent-helper.socket`) that takes the agent's uid
  from the socket: `pkexec`'s built-in text agent gets `No session for cookie` for everyone (polkit-org/polkit#686,
  #47). `pkttyagent` and Omarchy's agent work (`test/vm/adminprompt.py`). A fresh polkit has the socket inactive until
  reboot.
- Polkit stops at the first rule that answers: `49-monarchy-identity.rules` sorts before `50-default` and names
  `wheel` too (directory groups can't join `wheel`).
- polkit offers every admin identity (`wheel` plus sudo groups) in the rule's order, and Omarchy's dialog asks as the
  first without saying whose password (#34): the rule lists an admin who asks first.
- The VM's ssh key was once committed (anchored `.gitignore` bug) and purged. Never commit `test/vm/images` or `keys`.
