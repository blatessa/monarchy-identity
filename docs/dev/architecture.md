# Architecture

The decisions behind monarchy-identity and what it changes on a machine. Details that the code states plainly (the
generated config files, option parsing) are left to the code.

## Scope

A single-purpose utility: connect an Omarchy machine's authentication (sign-in, lock screen, `sudo`, `ssh`) to a
directory, and keep that working. Directories are providers ([Writing a provider](writing-a-provider.md)); Active
Directory is the first, not the default assumption. It owns:

- **Enrollment and leaving** (registering with the directory, and the authentication config that goes with it).
- **Authorization that the directory provides**: who may sign in, `sudo` for directory groups, offline credential
  lifetime. A provider feature belongs here if it's about authenticating or authorizing directory users.
- **Keeping authentication working across updates** (re-applying our edits after package transactions).
- **A machine-readable status** of the above, so other tools can build on it.

It does not own, and should not grow: device posture or compliance checks, inventory, privilege removal from local
users, boot hardening, tamper resistance, or undo machinery beyond `leave`. Those belong to an MDM or agent, which can
call this tool. When in doubt, ask: would this make sense in a plain Linux directory client?

Security is in scope: input validation, deny-by-default, PAM rules that can't lock out local users, secrets that never
hit a command line or disk.

## Packages

- `monarchy-identity` (`packaging/PKGBUILD`): CLI, providers, hooks, login theme. Installing changes nothing until
  `enroll`. Removing it while enrolled runs `leave` (`pre_remove`). The pacman hook runs `reassert` after our own
  upgrades too, so an enrolled machine picks up what a new version adds.
- The PKGBUILD builds the `v$pkgver` tag tarball, as Omarchy's package repo (`omacom/omarchy-pkgs`) requires; that
  repo's copy carries the checksum (ours says `SKIP`: the file is inside the tarball it would checksum).
  `packaging/build-local.sh` builds from a checkout (CI, the lab) by packing the working tree under the tarball's name.

### Directory clients

A provider's directory client is its own package, never bundled into `monarchy-identity`. Our package is `arch=any`
scripts that release on their own schedule; a client is usually compiled, has its own security releases and licence,
and is dead weight (more installed sign-in code) on a laptop that uses a different directory. `monarchy-identity`
lists each client in `optdepends`, and the provider's `enroll` refuses, before changing anything, with the exact
package to install when its client is missing.

**Entra ID: himmelblau** (the only complete Linux client: PAM, NSS and the device broker). It isn't in the Arch
repositories and the AUR package is unmaintained, so we contributed a recipe to `omacom/omarchy-pkgs`
(`pkgbuilds/himmelblau`), where laptops get it and its security fixes through `omarchy update`. There's no copy here:
the lab installs it from that repo like a laptop does. `enroll` never installs packages (pacman's job, and our pacman
hook would run `reassert` against the lock `enroll` holds).

- Built from upstream's public release tags (GPL-3.0). Upstream's prebuilt stable DEB/RPM packages are
  subscription-only; we don't use or redistribute them.
- Pinned to the current stable major (4.x): the recipe's upstream watch only matches 4.x tags, so point releases
  arrive automatically, and a himmelblau security release is a himmelblau package bump, not a `monarchy-identity`
  release. Moving to a new major is a deliberate change, tested in
  the lab against the test tenant.
- Rejected: bundling it into our package (above); shipping it only from our GitHub releases (installed by hand, fixes
  don't arrive with `omarchy update`); waiting for an official Arch package (no sign of one); writing our own Entra
  client (device registration, the token broker and MFA are a large security-sensitive client, out of scope).
- Unlike upstream's packaging, installing it configures nothing (the Arch norm, as with sssd): no PAM or nsswitch
  edits, and the files that act on their own (sshd drop-in, display manager override, browser policies) are examples
  under `/usr/share/doc/himmelblau`. Upstream's scriptlet also re-adds nsswitch entries on every upgrade, which would
  undo `leave`. `enroll entra` makes these edits itself.

## Layers

1. **Core CLI** (`bin/monarchy-identity`): `status | enroll | leave | policy | reassert | install-hooks |
   providers`. Parses the options every directory shares, runs the provider named in the config file
   for the directory part, and does the shared steps (PAM, SDDM, sudoers, policy state) around it. State-changing
   commands take `flock /run/monarchy-identity.lock` so a hook-triggered `reassert` can't interleave with
   `enroll`/`leave`.
2. **Providers** (`providers/<name>/`): the directory-specific part. See [Writing a provider](writing-a-provider.md).
3. **Shared helpers** (`lib/common.sh`, `lib/pamedit.py`).

## Enrollment order, and why

Every provider follows the same order: check, register, prove the directory answers, then PAM. The core validates the
shared options before the provider runs, and edits PAM only after the provider's `enroll` succeeded. The AD provider's
`enroll` checks everything it can against the directory **before** joining: the join password, that each `--groups`
entry exists, and whether a computer account of that name already belongs to another machine (it may reuse one only if
this machine is already joined with it, `net ads testjoin -P`, or with `--replace-computer-account`). Then it joins,
starts sssd, waits until a group resolves through sssd, and only then edits PAM.

There is no rollback. A failure after the join leaves PAM untouched; re-running `enroll` picks up where it stopped,
and `leave` cleans up. The core records the enrollment just before it edits PAM, so a failure in one of its own steps
still leaves something `leave` and a re-run know about. The join password is read from a prompt, a 0600 file or stdin, never argv.

## Files on an enrolled machine (AD provider)

The PAM, nsswitch, SDDM and sudoers rows apply to every provider; the rest are the AD provider's.

| Path | Change | On `leave` |
|---|---|---|
| `/etc/pam.d/system-auth`, `/etc/pam.d/omarchy-lock-password` | The provider's module (`pam_sss`) and `pam_mkhomedir`, between `# BEGIN/END monarchy-identity` | Block removed |
| `/etc/nsswitch.conf` | `sss` added to `passwd`, `group`, `shadow` | `sss` removed |
| `/etc/sssd/sssd.conf`, `/etc/krb5.conf`, `/etc/samba/smb.conf` | Written, with a `# managed by monarchy-identity` first line | Deleted if they carry the marker |
| `/etc/krb5.keytab` | Machine keytab | Deleted |
| `/etc/sddm.conf.d/zz-monarchy-identity.conf` | Autologin off (must sort after Omarchy's `autologin.conf`) | Deleted |
| `/etc/sddm.conf.d/zz-monarchy-identity-theme.conf` | Selects `sddm-theme/monarchy-identity` | Deleted |
| `/etc/pam.d/sddm` | `pam_exec` rules running `lib/password-expired` ([expired passwords](#expired-passwords-at-the-login-screen)), or for a provider with `login_steps`, `lib/login-steps` ([more than a password](#more-than-a-password-at-the-login-screen)), between `# BEGIN/END monarchy-identity` | Blocks removed |
| `/etc/pam.d/monarchy-identity-expired` or `/etc/pam.d/monarchy-identity-login-steps` | The provider's module alone, marked; the helper's own sign-in | Deleted if marked |
| `/etc/sddm.conf.d/zz-monarchy-identity-session.conf` | `[Wayland]`/`[X11] SessionCommand=lib/sddm-session` | Deleted |
| `/etc/sudoers.d/50-monarchy-identity` | `%group ALL=(ALL:ALL) ALL`, visudo-validated, 0440 | Deleted |
| `/etc/sudoers.d/51-monarchy-identity-theme` | The sign-in groups (or users) may run Omarchy's `omarchy-theme-set-browser-policy` with a six-hex-digit argument without a password; absent for `--mode any` | Deleted |
| `/etc/polkit-1/rules.d/49-monarchy-identity.rules` | Admin identities for graphical admin prompts: `wheel` plus the sudo groups, with an admin who asks listed first (only when polkit's rules directory exists) | Deleted |
| `/etc/monarchy-identity/config.toml` | What the admin chose: who may sign in, sudo groups, offline days, autologin, login theme | Emptied |
| `/var/lib/monarchy-identity/state.toml` | What enroll did: the provider, and the provider's own keys (for AD: realm, server, computer name, OU) | Deleted |

The admin's choices and the enrollment are separate files so an MDM can manage `config.toml` without clobbering the
enrollment, and enrolling never rewrites keys the MDM didn't mention. Being enrolled means `state.toml` names a
provider. Enrollments from before the split kept everything in `config.toml`: until a root command runs, the state is
read from there, and the first `enroll`, `policy set`, `reassert` or `leave` moves every key that isn't the admin's
into `state.toml` (`state_migrate`, under the lock).

Both files (and each provider's `pam.conf`) are a flat subset of TOML: `key = "value"` lines, `#` comments and blank
lines, values escaped with `\"`, `\\`, `\n`, `\t`. `lib/common.sh` reads and writes them (`conf_get`/`conf_set`,
`state_get`/`state_set`); a line outside that shape, an unknown escape or a repeated key stops every command that reads
the file, naming the line, rather than falling back to defaults. An MDM may manage `config.toml`, so it is parsed
strictly, not guessed at.

Everything else stays in `/etc` drop-ins or marked blocks; never edit `/usr/share/omarchy/` (package-owned).

## The Entra ID provider

Decided in #71 from the himmelblau spike ([findings](findings.md)). Entra fits the provider contract; the core knows
nothing about it beyond the `pam.conf` switches ([below](#the-pam-edit)).

- **Enroll doesn't register the device.** It checks the tenant (public OpenID discovery), looks up the policy's names,
  writes its settings as a drop-in, `/etc/himmelblau/himmelblau.conf.d/50-monarchy-identity.conf` (marked; the
  himmelblau package owns `himmelblau.conf`, and removing the package would move an edited one aside), adds `himmelblau` to `passwd`, `group` and `shadow` in nsswitch
  and starts the daemons. The laptop registers itself at the first sign-in, so there is no per-laptop token for an MDM
  to hand out. Never `aad-tool configure-pam`: the core edits PAM as for any provider.
- **Group names, looked up with an app registration.** Admins think in names, but groups don't resolve through NSS
  before the device is registered (users do), so enroll needs a credential: an app registration with `Group.Read.All`
  and `User.Read.All` and its client secret (`--client-id`, `--password-file` or typed). Rejected: object ids on the
  command line (unreadable, and a typo is a valid-looking id); a device-code sign-in at enroll (an MDM can't answer
  it). The secret is used for the lookup and not kept. Ids go into `pam_allow_groups`, names stay in `config.toml`, and
  `state.toml` keeps `name=id` so `policy set` with known names needs no secret.
- **Default deny.** himmelblau lets every tenant user in when `pam_allow_groups` is unset, so enroll always writes it;
  only `--mode any` leaves it out. `--users` become full sign-in names in the same list (a bare name gets the tenant's
  domain).
- **Usernames and ids.** Short names and full sign-in names both resolve; a local account of the same name wins. UIDs
  and GIDs are derived from the tenant and object id, so they're the same on every laptop. Home is
  `/home/<object id>` with a link at the sign-in name, made by himmelblau (hence `mkhomedir = "false"`).
- **sudo** uses the core's `%group` sudoers rule: Entra groups resolve by name through NSS once registered.
  himmelblau's own `sudo_groups` isn't used, so every provider's sudo works the same way.
- **Offline**: `[offline_breakglass] enabled = true`, which caches a password verifier at each online sign-in. Its
  `ttl` only applies to breakglass switched on by hand, not to automatic offline sign-in, and there's no verifier
  lifetime, so `--offline-days` is refused rather than ignored.
- **MFA at the login screen.** Entra asks for a second step (a code, or a number to approve on the phone) at a
  person's first sign-in on a laptop and when it wants MFA again. After that the laptop's sign-in token satisfies it,
  and the login screen, lock screen and `sudo` take the password alone. SDDM can't carry the second step, so
  `login_steps = "true"` ([below](#more-than-a-password-at-the-login-screen)).
  `enable_hello = false` for now; Hello PIN is the likely next default (MFA once at setup, offline built in).
  Password-only `ssh` is refused by himmelblau (its remote-services list); we keep that default, and `ssh` asks for
  the code every time.
- **Leave** stops the daemons, clears himmelblau's registration, caches and the tokens systemd keeps for it, and
  removes the config and nsswitch entries. It doesn't delete the device object in Entra (that needs a device
  permission on the app registration, more than enroll asks for): it says so with the device ID, as AD's `leave`
  does without `--admin`. Entra allows several devices of one name, so the ID is how an admin finds the stale one.
- **Enrolling again** with the same tenant keeps the registration (himmelblau's device id is in its own cache, not
  the config we write). Another tenant is refused until `leave`, compared by tenant id: himmelblau would stay
  registered with the first. Entra has nothing to reject up front: a reinstalled laptop just registers a new device.

## The PAM edit

This is the one place a mistake locks people out, so the rules are the core's and the provider only names its module
and arguments (`providers/<name>/pam.conf`). `lib/pamedit.py apply FILE MODULE [TYPE=ARGS ...]` inserts, between
markers (here for the AD provider, `pam_sss.so auth=forward_pass`):

```text
-auth      [success=1 default=ignore]  pam_localuser.so
-auth      [success=N default=ignore]  pam_sss.so forward_pass
-account   [success=1 default=ignore]  pam_localuser.so
-account   [success=N user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad]  pam_sss.so
-password  [success=1 default=ignore]  pam_localuser.so
-password  [success=N default=ignore]  pam_sss.so
session    required   pam_mkhomedir.so umask=0077
-session   [success=1 default=ignore]  pam_localuser.so
-session   optional   pam_sss.so
```

`N` is computed from the file so a module success skips `pam_unix`/`pam_faillock`, including next to Omarchy's
`pam_systemd_home` lines. The `-` prefix and the `ignore` mappings mean a missing module or stopped daemon can't fail a
local login; only a definite answer from the module can. `pam_localuser` (part of Linux-PAM) skips the module for
names in `/etc/passwd`, so the directory never answers for a local account, even one with a directory user's name:
nsswitch already resolves the local entry first, and without the guard the directory's "not allowed" locked the owner
out of their account, or the directory user's password opened it, local groups (`wheel`) included. `lib/password-expired`
skips local accounts for the same reason. Module names and arguments are restricted to characters that
can't start another rule or control field. `remove FILE` restores the file byte for byte, whatever module was
inserted.

Four `pam.conf` switches cover modules that do part of this themselves or ask for more (Entra's `pam_himmelblau` uses
all four):

- `mkhomedir = "false"`: no `pam_mkhomedir`. himmelblau makes `/home/<object id>` and a `/home/<sign-in name>` link at
  session open; `pam_mkhomedir`, first in the stack, would make a real directory at the link's path.
- `expired_password_screen = "false"`: no expired-password rules on `sddm` (below), so SDDM sign-in doesn't ask the
  directory twice. Entra passwords are changed in Entra.
- `login_steps = "true"`: instead of the expired-password rules, the login screen's service asks the directory once,
  with a code if it wants one ([below](#more-than-a-password-at-the-login-screen)).
- `auth_retry_on_abort = "true"`: the auth rule twice, the first `[success=N+1 abort=ignore default=1]` so only an
  abort reaches the second. himmelblau aborts the first sign-in after the network drops (it learns it's offline) and
  answers from its offline cache when asked again; without the retry that first offline sign-in fails.

`system-auth` and `omarchy-lock-password` get the module; `sddm` gets the expired-password rules below. Every other service either includes `system-auth` and so
gets directory sign-in with no edit of its own, or is deliberately left alone:

- **Admin prompts (`polkit-1`)** include `system-auth` (a vendor file in `/usr/lib/pam.d/`), so a directory admin
  answers with their directory password. polkit asks in a sandboxed, socket-activated helper (`polkit-agent-helper@`,
  `ProtectSystem=strict`, `PrivateNetwork`); `pam_sss` works there because it only needs sssd's socket. Which accounts
  count as admins is `49-monarchy-identity.rules` (above). Omarchy's dialog asks as the first account polkit offers and
  shows no choice, so the rule lists the person asking first when they are an admin: they answer with their own
  password. Showing or choosing the account is the dialog's, and upstream's. `e2e.sh` answers a real prompt.
- **`su` is not edited.** Arch's `su`/`su-l` call `pam_unix` directly rather than including `system-auth`, so a
  directory user's password never works there; root `su` to anyone still does (`pam_rootok`). Editing a stack we
  don't otherwise touch would be a second lockout surface to keep across updates for a command Omarchy doesn't use;
  directory admins have `sudo` (and `sudo -iu USER`). `test/unit/pam.sh` asserts no other service is touched.

## Expired passwords at the login screen

SDDM has no way to ask for a new password: it never calls `pam_chauthtok` (upstream sddm#776), so the directory's
"new password required" from the account stack is just a failed sign-in. `pamedit.py greeter /etc/pam.d/sddm HELPER`
adds, to the login screen's service only:

```text
auth        include     system-login
-auth       optional    pam_exec.so quiet expose_authtok HELPER     # right after the real password check
-account    [success=done default=ignore]  pam_exec.so quiet HELPER  # first in account
account     include     system-login
```

- **auth:** `lib/password-expired` first deletes this user's mark, then re-authenticates with the password the stack
  just accepted through `/etc/pam.d/monarchy-identity-expired` (the provider's module only) and marks the sign-in
  (`/run/monarchy-identity/password-change/USER`) if account management answers `PAM_NEW_AUTHTOK_REQD`. It can't ask in
  the account phase: sssd only reports expiry in the handle that authenticated. A wrong password dies at faillock
  before this rule, so the directory sees it once (lab: `badPwdCount` +1).
- **account:** success, ending the stack, only for a sign-in marked in the last 120 s; otherwise ignored. For that
  sign-in `system-login`'s account checks (`pam_access`, `pam_time`, `pam_nologin`) don't run; Omarchy configures
  none, and who may sign in is still enforced by the re-check's account step (an expired user outside the allowed
  groups gets no mark).
- **session:** SDDM's `SessionCommand` is `lib/sddm-session`. Marked: a Hyprland with `lib/password-change.lua` (no
  binds) runs `foot`, with an empty config and its shortcuts that start programs (a new terminal, the URL opener) off, with a `gum` header and the real `passwd`; changed → `exec` SDDM's own `wayland-session` with the
  session's arguments, otherwise exit 0 (exit 1 would be read as SDDM's helper failing to authenticate, leaving a black
  screen). An X11 session can't host it: marked → exit 0.
- **SDDM reads its config once.** Until it restarts after enroll, it would run the stock session command and the
  person would reach the desktop unchanged, so the helper only marks when the SDDM process (pam_exec ← sddm-helper ←
  sddm) started after `zz-monarchy-identity-session.conf` was written. Until then an expired password is refused, as
  before. Removing the package leaves a running SDDM pointing at a deleted session command; the scriptlet says to
  restart.

## More than a password at the login screen

SDDM answers every PAM prompt with the password it collected (`Display::slotRequestChanged`) and its greeter can't
answer anything else. pam_himmelblau, after a refusal, starts the sign-in over inside the same `pam_authenticate`. So
SDDM sends the password as the authenticator code, and sends a mistyped password again, forever, until Entra's smart
lockout throttles the account (reported upstream, himmelblau#1882). For a provider with `login_steps = "true"`,
`pamedit.py login-steps /etc/pam.d/sddm HELPER` puts two rules in the login screen's service, before
`auth include system-login`:

```text
-auth  [success=done default=ignore]  pam_exec.so quiet stdout expose_authtok HELPER
-auth  [success=die default=ignore]   pam_exec.so quiet HELPER refused
```

- **The first rule:** `lib/login-steps` signs in through `/etc/pam.d/monarchy-identity-login-steps` (the provider's
  module alone). It answers the first prompt with the password and a second, different one with a code, if it has
  one. Our theme sends the password and a code as two lines of one answer.
  - **Signed in:** success, and the auth stack ends there. The account stack still decides who may sign in.
  - **The password asked again:** refused; the second rule then fails the stack at once (`die` on its success gives
    `PAM_PERM_DENIED`).
  - **A code wanted and none given:** also refused, but nothing is sent for the code. The helper first prints the
    directory's message and `monarchy-identity: code wanted`. `pam_exec`'s `stdout` passes each line to SDDM as an
    info message. The theme shows the message and a code line, keeps the password, and sends both on the next try.
  - **A message left standing** (the number to enter on the phone while the module waits for the approval) is
    printed after a few seconds, so the theme shows it.
  - **Local accounts, or no answer** (daemon down): both rules are ignored, and the normal stack decides, as before.
- **Each try asks Entra once:** the password, plus the code when one is given. A wrong code is one refusal.

A screen after the login screen was tried first, as for expired passwords, and can't work. Until someone has
completed a sign-in on the laptop, himmelblau resolves them by name but not by user id. logind's `CreateSession`
looks them up by id, so it fails, and the session (Hyprland) can't start. So the code has to be taken before the
session, at the login screen. That also means nothing runs as the person before the second factor.

Approval on the phone was checked by hand on the real login screen. The theme showed "Open your Authenticator app,
and enter the number '63' to sign in" while the helper waited, the number was approved, and the desktop started. It
needs a person with a phone, so no suite covers it. Entra's system-preferred MFA picks the push whenever one is
registered, whatever the user's default, so most people will see this rather than the code line.

## Keeping it working after updates

`reassert` re-applies PAM, SDDM and sudoers edits from `config.toml` and `state.toml`, after the provider's own `reassert` (for AD:
nsswitch, and starting sssd if stopped). It runs:

- from the pacman hook (`packaging/monarchy-identity.hook`) after transactions on `pambase`, the directory clients (`sssd`,
  `himmelblau`), `filesystem`, `omarchy`, `omarchy-settings`;
- from the optional per-user Omarchy post-update hook (`install-hooks`), via `sudo -n`.

There is deliberately no file watcher: guarding config against a local admin is an MDM's job, not ours.

The AD provider's generated sssd/krb5/samba config is in `providers/ad/lib.sh`; its state keys are in `ad_save_state`.
