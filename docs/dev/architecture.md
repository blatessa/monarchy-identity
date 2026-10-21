# Architecture

What monarchy-identity changes on a machine, and the decisions behind it. What the code states plainly is left to the
code.

## Scope

Connect an Omarchy machine's authentication (sign-in, lock screen, `sudo`, `ssh`) to a directory and keep it working:
enrollment and `leave`, directory-provided authorization (who may sign in, sudo groups, offline lifetime), re-applying
the config after updates, and `status --json` for other tools. Not: device posture or compliance, inventory, hardening,
tamper resistance, undo machinery (timers, backups, rollback). Those belong to an MDM. Test: would it belong in a plain
Linux directory client?

## Packages

- `monarchy-identity` (`packaging/PKGBUILD`): CLI, providers, hooks, login theme, docs. Installing changes nothing.
  `pre_remove` runs `leave`. The pacman hook runs `reassert` after our own upgrades too.
- The PKGBUILD builds the `v$pkgver` tag tarball, as `omacom/omarchy-pkgs` requires; that repo's copy carries the
  checksum (ours is `SKIP`: the file is inside the tarball). `packaging/build-local.sh` builds from a checkout.

### Directory clients

Each provider's client is its own package and an `optdepends`, never bundled: clients are compiled, have their own
security releases, and are dead weight for other directories. `enroll` refuses, before changing anything, with the
package to install. `enroll` never installs packages.

**Entra ID: himmelblau**, the only complete Linux client (PAM, NSS, device broker). Not in the Arch repos, AUR package
unmaintained, so we contributed a recipe to `omacom/omarchy-pkgs` (#1274, himmelblau 4.0.6); laptops get it and its
fixes through `omarchy update`. Built from upstream's release tags (GPL-3.0); upstream's prebuilt DEB/RPMs are
subscription-only. The recipe's upstream watch tracks 4.x. Installing it configures nothing: no PAM or nsswitch edits
(upstream's scriptlet re-adds nsswitch entries on every upgrade, which would undo `leave`), and the sshd, display
manager and browser files are examples under `/usr/share/doc/himmelblau`.

## Layers

1. `bin/monarchy-identity`: parses the shared options, runs the provider, does PAM, SDDM, sudoers and the policy state.
   State-changing commands hold `flock /run/monarchy-identity.lock`.
2. `providers/<name>/`: the directory part ([Writing a provider](writing-a-provider.md)).
3. `lib/common.sh`, `lib/pamedit.py`.

## Enrollment order

Check, register, prove the directory answers, then PAM. The core validates shared options first and edits PAM only
after the provider's `enroll` succeeded. AD checks the join password, every `--groups` entry, and whether the computer
name belongs to another machine (reused only if this machine is joined with it, `net ads testjoin -P`, or with
`--replace-computer-account`), then joins, starts sssd, waits until a group resolves, and then the core edits PAM.

No rollback: a failure after the join leaves PAM untouched, a re-run picks up where it stopped, `leave` cleans up. The
core records the enrollment just before editing PAM. Secrets come from a prompt, a mode-600 file or stdin, never argv.

## Files on an enrolled machine

PAM, nsswitch, SDDM, sudoers and polkit rows apply to every provider; the sssd/krb5/samba rows are AD's (Entra's are
[below](#the-entra-id-provider)).

| Path | Change | On `leave` |
|---|---|---|
| `/etc/pam.d/system-auth`, `/etc/pam.d/omarchy-lock-password` | The provider's module and `pam_mkhomedir`, between `# BEGIN/END monarchy-identity` | Block removed |
| `/etc/nsswitch.conf` | `sss` (Entra: `himmelblau`) on `passwd`, `group`, `shadow` | Removed |
| `/etc/sssd/sssd.conf`, `/etc/krb5.conf`, `/etc/samba/smb.conf` | Written with a `# managed by monarchy-identity` first line | Deleted if marked |
| `/etc/krb5.keytab` | Machine keytab | Deleted |
| `/etc/sddm.conf.d/zz-monarchy-identity.conf` | Autologin off (sorts after Omarchy's `autologin.conf`) | Deleted |
| `/etc/sddm.conf.d/zz-monarchy-identity-theme.conf` | Selects `sddm-theme/monarchy-identity` | Deleted |
| `/etc/pam.d/sddm` | `pam_exec` rules for `lib/password-expired` ([expired passwords](#expired-passwords-at-the-login-screen)) or, with `login_steps`, `lib/login-steps` ([more than a password](#more-than-a-password-at-the-login-screen)), marked | Blocks removed |
| `/etc/pam.d/monarchy-identity-expired`, `/etc/pam.d/monarchy-identity-login-steps` | The provider's module alone, for the helpers | Deleted if marked |
| `/etc/sddm.conf.d/zz-monarchy-identity-session.conf` | `[Wayland]`/`[X11] SessionCommand=lib/sddm-session` | Deleted |
| `/etc/sudoers.d/50-monarchy-identity` | `%group ALL=(ALL:ALL) ALL`, visudo-checked, 0440 | Deleted |
| `/etc/sudoers.d/51-monarchy-identity-theme` | The sign-in groups may run `omarchy-theme-set-browser-policy` with a six-hex-digit argument, no password (Omarchy grants it to `wheel` only); absent for `--mode any` | Deleted |
| `/etc/polkit-1/rules.d/49-monarchy-identity.rules` | Admin identities for admin prompts: `wheel` plus the sudo groups, an admin who asks listed first | Deleted |
| `/etc/monarchy-identity/config.toml` | The admin's choices: policy, sudo groups, offline days, autologin | Emptied |
| `/var/lib/monarchy-identity/state.toml` | What enroll did: the provider and its keys | Deleted |

`config.toml` and `state.toml` are separate so an MDM can manage the first without touching the enrollment; enrolled
means `state.toml` names a provider. Both (and `pam.conf`) are flat TOML: `key = "value"`, `#` comments, escapes `\"`
`\\` `\n` `\t`. Anything else, an unknown escape or a repeated key stops every command that reads the file, naming the
line. Never edit `/usr/share/omarchy/`.

## The Entra ID provider

- **Enroll doesn't register the device.** It checks the tenant (OpenID discovery), looks up the policy's names, writes
  `/etc/himmelblau/himmelblau.conf.d/50-monarchy-identity.conf` (a drop-in: the package owns `himmelblau.conf`), adds
  `himmelblau` to nsswitch and starts the daemons. The laptop registers at the first sign-in, so there's no
  per-laptop token. The core edits PAM; never `aad-tool configure-pam`.
- **Group names need an app registration** (`Group.Read.All`, `User.Read.All`, client secret): groups don't resolve
  through NSS before the device is registered. Rejected: object ids on the command line, a device-code sign-in at
  enroll (an MDM can't answer it). The secret isn't kept. Ids go into `pam_allow_groups`, names stay in `config.toml`,
  `state.toml` keeps `name=id` so `policy set` with known names needs no secret.
- **Default deny:** unset `pam_allow_groups` lets the whole tenant in, so it's always written except for `--mode any`.
  `--users` become full sign-in names in the same list.
- **Names and ids:** short and full sign-in names resolve; a local account of the same name wins. UIDs/GIDs derive
  from the tenant and object id (same on every laptop). `home_attr = home_alias = cn`: home is `/home/alice`, made by
  `pam_mkhomedir` from `/etc/skel` (himmelblau's own copy stops partway, [findings](findings.md)).
- **sudo:** the core's `%group` rule; Entra groups resolve by name once registered. himmelblau's `sudo_groups` unused.
- **Offline:** `[offline_breakglass] enabled = true` caches a verifier at each online sign-in. No verifier lifetime
  exists, so `--offline-days` is refused.
- **MFA:** asked at a person's first sign-in on a laptop and when Entra wants it again; the laptop's token covers the
  rest. SDDM can't carry it: `login_steps = "true"`. `enable_hello = false` (#90). Password-only `ssh` is refused by
  himmelblau; kept.
- **Leave** stops the daemons, clears himmelblau's registration, cache and fd store, removes the config and nsswitch
  entries, and prints the device ID (deleting the device needs more permission than enroll asks for; Entra allows
  duplicate names, so the ID matters).
- **Enrolling again** with the same tenant keeps the registration (it's in himmelblau's cache). Another tenant (by id)
  is refused until `leave`.

## The PAM edit

The core owns the rules; a provider names its module and arguments in `providers/<name>/pam.conf`.
`lib/pamedit.py apply FILE MODULE [TYPE=ARGS ...]` inserts between markers (AD, `pam_sss.so auth=forward_pass`):

```text
-auth      [success=1 default=ignore]  pam_localuser.so
-auth      [success=N perm_denied=die acct_expired=die default=ignore]  pam_sss.so forward_pass
-account   [success=1 default=ignore]  pam_localuser.so
-account   [success=N user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad]  pam_sss.so
-password  [success=1 default=ignore]  pam_localuser.so
-password  [success=N default=ignore]  pam_sss.so
session    required   pam_mkhomedir.so umask=0077
-session   [success=1 default=ignore]  pam_localuser.so
-session   optional   pam_sss.so
```

- `N` is computed from the file so success skips `pam_unix`/`pam_faillock`, also next to Omarchy's `pam_systemd_home`.
- `-` and the `ignore` mappings: a missing module or stopped daemon can't fail a local login.
- `perm_denied=die acct_expired=die`: a disabled, locked or expired account ends with the directory's answer instead of
  `pam_unix`'s `Authentication failure`, so the login screen can say why ([below](#why-a-sign-in-failed)).
- `pam_localuser` skips the module for names in `/etc/passwd`. Without it the directory decided for a local account
  of the same name (refusing the owner, or letting the directory password in with `wheel`).
- Module names and arguments can't contain characters that start another rule. `remove FILE` restores the file byte
  for byte.

`pam.conf` switches (Entra's `pam_himmelblau` uses the last three):

- `mkhomedir = "false"`: no `pam_mkhomedir`.
- `expired_password_screen = "false"`: no expired-password rules on `sddm`.
- `login_steps = "true"`: the login-steps rules on `sddm` instead ([below](#more-than-a-password-at-the-login-screen)).
- `auth_retry_on_abort = "true"`: the auth rule twice, the first `[success=N+1 abort=ignore ... default=1]`. himmelblau
  aborts the first sign-in after the network drops and answers from its cache when asked again.

Other services: everything that includes `system-auth` gets directory sign-in, including `polkit-1` (a vendor file in
`/usr/lib/pam.d/`; its sandboxed helper only needs the client's socket). `su`/`su-l` on Arch use `pam_unix` directly
and are not edited (another lockout surface for a command Omarchy doesn't use; directory admins have `sudo -iu`).
`test/unit/pam.sh` asserts nothing else is touched.

## Expired passwords at the login screen

SDDM never calls `pam_chauthtok` (sddm#776): "new password required" is just a failed sign-in.
`pamedit.py greeter /etc/pam.d/sddm HELPER` adds:

```text
auth        include     system-login
-auth       optional    pam_exec.so quiet expose_authtok HELPER     # after the real password check
-account    [success=done default=ignore]  pam_exec.so quiet HELPER  # first in account
account     include     system-login
```

- **auth:** `lib/password-expired` deletes the user's mark, re-authenticates with the accepted password through
  `/etc/pam.d/monarchy-identity-expired` (the module alone), and marks the sign-in
  (`/run/monarchy-identity/password-change/USER`) if account management answers `PAM_NEW_AUTHTOK_REQD` (sssd only
  reports expiry in the handle that authenticated). A wrong password fails at faillock before this rule.
- **account:** success, ending the stack, only for a sign-in marked in the last 120 s. Who may sign in is still
  enforced by the re-check's account step.
- **session:** `SessionCommand` is `lib/sddm-session`. Marked: Hyprland with `lib/password-change.lua` (no binds)
  running `foot` (empty config, program-starting shortcuts off) with `passwd`; changed → `exec` SDDM's
  `wayland-session`, otherwise exit 0 (exit 1 leaves a black screen). X11 sessions: exit 0.
- SDDM reads its config once, so the helper only marks when the running SDDM started after
  `zz-monarchy-identity-session.conf` was written. Until then an expired password is refused.

## More than a password at the login screen

SDDM answers every PAM prompt with the password it collected (`Display::slotRequestChanged`). pam_himmelblau restarts
the sign-in after a refusal inside the same `pam_authenticate`, so SDDM would send the password as the MFA code, and a
mistyped password again, until Entra's smart lockout throttles the account (himmelblau#1882).
`pamedit.py login-steps /etc/pam.d/sddm HELPER` adds, before `auth include system-login`:

```text
-auth  [success=done default=ignore]  pam_exec.so quiet stdout expose_authtok HELPER
-auth  [success=die default=ignore]   pam_exec.so quiet HELPER refused
```

`lib/login-steps` signs in through `/etc/pam.d/monarchy-identity-login-steps` (the module alone, auth and account). The theme sends up to
three lines as the password: password, code, new password. The helper answers the first prompt with the password,
`New password:`/`Confirm password:` with the new password, and any other prompt once with the code. Each try asks Entra
once. Lines it prints reach the theme as SDDM info messages (`pam_exec stdout`):

| Outcome | Result | Printed |
|---|---|---|
| Signed in | auth ends, success; the account stack still applies the policy | |
| Signed in, its account check says no | refused | "This account can't sign in on this laptop. Ask IT.", `monarchy-identity: refused` |
| Password or code asked again | refused (rule 2: `die`) | the directory's reason, `monarchy-identity: refused` |
| Code wanted, none given | refused, nothing sent for the code | the message, `monarchy-identity: code wanted` |
| New password wanted, none given | refused | the message, `monarchy-identity: new password wanted` |
| New password asked again | refused | why (too short, Entra's rule) |
| Past the new-password prompts | continues | `monarchy-identity: password changed` |
| Message standing > 3 s (number to approve) | waits | the message |
| Local account, daemon down | both rules ignored | |

Prompts are matched by text with `LC_ALL=C.UTF-8`. The module logs to stdout, so the helper moves its own stdout
aside (else people saw `PAM_CONV_ERR`). Entra's `AADSTS…` messages lose the code and the trace IDs; AADSTS50058 and 50133 (Entra wants a browser, e.g. to
change a password on a joined laptop) become "sign in at myaccount.microsoft.com first".

A screen after the login screen (as for AD) can't work for MFA: before a first completed sign-in himmelblau resolves
the user by name but not by uid, so logind's `CreateSession` fails and no session can start.

Approval on the phone was checked by hand ("Open your Authenticator app, and enter the number '63'"); no suite covers
it. Entra's system-preferred MFA picks the push whenever one is registered.

## Keeping it working after updates

`reassert` runs the provider's `reassert` (nsswitch, daemon running), then re-applies PAM, SDDM and sudoers from
`config.toml` and `state.toml`. It runs from the pacman hook (`packaging/monarchy-identity.hook`: `pambase`, `sssd`,
`himmelblau`, `filesystem`, `omarchy`, `omarchy-settings`, and our own package) and from the optional Omarchy
post-update hook (`install-hooks`, via `sudo -n`). No file watcher.

## Why a sign-in failed

The theme turns what SDDM passed on during a try (module messages, then `pam_strerror` of the result) into a sentence:
`sddm-theme/monarchy-identity/reasons.js`, recorded cases in [findings](findings.md#pam-sssd). It says what the
directory said, as Windows does. AD itself only reports disabled or expired after the right password; a lockout shows
whatever the password. Entra refusals keep Entra's words (login-steps above).

Both `sddm` edits (`greeter`, `login-steps`) put Omarchy's faillock check first, with the limits from system-auth's
`preauth` rule minus `silent`:

```text
-auth  [auth_err=die default=ignore]  pam_faillock.so preauth deny=10 unlock_time=120
```

It ends the sign-in only when faillock says locked, with its message. It's also ahead of login-steps, which ends the
stack when signed in: before, an Entra user locked by faillock still signed in at the login screen.

