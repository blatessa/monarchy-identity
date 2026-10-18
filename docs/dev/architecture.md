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
| `/etc/pam.d/sddm` | Two `pam_exec` rules running `lib/password-expired`, between `# BEGIN/END monarchy-identity` ([expired passwords](#expired-passwords-at-the-login-screen)) | Blocks removed |
| `/etc/pam.d/monarchy-identity-expired` | The provider's module alone (`auth` + `account`), marked; the helper's re-check | Deleted if marked |
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

## The PAM edit

This is the one place a mistake locks people out, so the rules are the core's and the provider only names its module
and arguments (`providers/<name>/pam.conf`). `lib/pamedit.py apply FILE MODULE [TYPE=ARGS ...]` inserts, between
markers (here for the AD provider, `pam_sss.so auth=forward_pass`):

```text
-auth      [success=N default=ignore]  pam_sss.so forward_pass
-account   [success=N user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad]  pam_sss.so
-password  [success=N default=ignore]  pam_sss.so
session    required   pam_mkhomedir.so umask=0077
-session   optional   pam_sss.so
```

`N` is computed from the file so a module success skips `pam_unix`/`pam_faillock`, including next to Omarchy's
`pam_systemd_home` lines. The `-` prefix and the `ignore` mappings mean a missing module or stopped daemon can't fail a
local login; only a definite answer from the module can. Module names and arguments are restricted to characters that
can't start another rule or control field. `remove FILE` restores the file byte for byte, whatever module was
inserted.

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
  binds) runs `foot` with a `gum` header and the real `passwd`; changed → `exec` SDDM's own `wayland-session` with the
  session's arguments, otherwise exit 0 (exit 1 would be read as SDDM's helper failing to authenticate, leaving a black
  screen). An X11 session can't host it: marked → exit 0.
- **SDDM reads its config once.** Until it restarts after enroll, it would run the stock session command and the
  person would reach the desktop unchanged, so the helper only marks when the SDDM process (pam_exec ← sddm-helper ←
  sddm) started after `zz-monarchy-identity-session.conf` was written. Until then an expired password is refused, as
  before. Removing the package leaves a running SDDM pointing at a deleted session command; the scriptlet says to
  restart.

## Keeping it working after updates

`reassert` re-applies PAM, SDDM and sudoers edits from `config.toml` and `state.toml`, after the provider's own `reassert` (for AD:
nsswitch, and starting sssd if stopped). It runs:

- from the pacman hook (`packaging/monarchy-identity.hook`) after transactions on `pambase`, `sssd`, `filesystem`,
  `omarchy`, `omarchy-settings`;
- from the optional per-user Omarchy post-update hook (`install-hooks`), via `sudo -n`.

There is deliberately no file watcher: guarding config against a local admin is an MDM's job, not ours.

The AD provider's generated sssd/krb5/samba config is in `providers/ad/lib.sh`; its state keys are in `ad_save_state`.
