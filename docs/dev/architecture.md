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
  `enroll`. Removing it while enrolled runs `leave` (`pre_remove`).
- `monarchy-identity-shell`: optional Quickshell bar widget; reads `status --json`. Display only.

## Layers

1. **Core CLI** (`bin/monarchy-identity`): `status | enroll | leave | policy | reassert | install-hooks |
   install-widget | providers`. Dispatches to the provider named in the config file; state-changing commands take
   `flock /run/monarchy-identity.lock` so a hook-triggered `reassert` can't interleave with `enroll`/`leave`.
2. **Providers** (`providers/<name>/`): the directory-specific part. See [Writing a provider](writing-a-provider.md).
3. **Shared helpers** (`lib/common.sh`, `lib/pamedit.py`).

## Enrollment order, and why

Every provider follows the same order: check, register, prove the directory answers, then PAM. The AD provider's
`enroll` checks everything it can against the directory **before** joining: the join password, that each `--groups`
entry exists, and whether a computer account of that name already belongs to another machine (it may reuse one only if
this machine is already joined with it, `net ads testjoin -P`, or with `--replace-computer-account`). Then it joins,
starts sssd, waits until a group resolves through sssd, and only then edits PAM.

There is no rollback. A failure after the join leaves PAM untouched; re-running `enroll` picks up where it stopped,
and `leave` cleans up. The join password is read from a prompt, a 0600 file or stdin, never argv.

## Files on an enrolled machine (AD provider)

The PAM, nsswitch, SDDM and sudoers rows apply to every provider; the rest are the AD provider's.

| Path | Change | On `leave` |
|---|---|---|
| `/etc/pam.d/system-auth`, `/etc/pam.d/omarchy-lock-password` | `pam_sss`/`pam_mkhomedir` block between `# BEGIN/END monarchy-identity` | Block removed |
| `/etc/nsswitch.conf` | `sss` added to `passwd`, `group`, `shadow` | `sss` removed |
| `/etc/sssd/sssd.conf`, `/etc/krb5.conf`, `/etc/samba/smb.conf` | Written, with a `# managed by monarchy-identity` first line | Deleted if they carry the marker |
| `/etc/krb5.keytab` | Machine keytab | Deleted |
| `/etc/sddm.conf.d/zz-monarchy-identity.conf` | Autologin off (must sort after Omarchy's `autologin.conf`) | Deleted |
| `/etc/sddm.conf.d/zz-monarchy-identity-theme.conf` | Selects `sddm-theme/monarchy-identity` | Deleted |
| `/etc/sudoers.d/50-monarchy-identity` | `%group ALL=(ALL:ALL) ALL`, visudo-validated, 0440 | Deleted |
| `/etc/monarchy-identity/config.toml` | Provider and policy state | Reset to `provider = "local"` |

Everything else stays in `/etc` drop-ins or marked blocks; never edit `/usr/share/omarchy/` (package-owned).

## The PAM edit

This is the one place a mistake locks people out. Today the inserted module is `pam_sss` (the AD provider); a provider
with another PAM module needs `pamedit.py` to take the module from the provider, with the same safety rules. `lib/pamedit.py apply|remove|check FILE` inserts, between markers:

```text
-auth      [success=N default=ignore]  pam_sss.so forward_pass
-account   [success=N user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad]  pam_sss.so
-password  [success=N default=ignore]  pam_sss.so
session    required   pam_mkhomedir.so umask=0077
-session   optional   pam_sss.so
```

`N` is computed from the file so a `pam_sss` success skips `pam_unix`/`pam_faillock`, including next to Omarchy's
`pam_systemd_home` lines. The `-` prefix and the `ignore` mappings mean a missing module or stopped sssd can't fail a
local login; only a definite answer from `pam_sss` can. `remove` restores the file byte for byte.

## Keeping it working after updates

`reassert` re-applies nsswitch, PAM, SDDM and sudoers edits from `config.toml` and starts sssd if stopped. It runs:

- from the pacman hook (`packaging/monarchy-identity.hook`) after transactions on `pambase`, `sssd`, `filesystem`,
  `omarchy`, `omarchy-settings`;
- from the optional per-user Omarchy post-update hook (`install-hooks`), via `sudo -n`.

There is deliberately no file watcher: guarding config against a local admin is an MDM's job, not ours.

The AD provider's generated sssd/krb5/samba config is in `providers/ad/lib.sh`; its state keys are in `sssd_save_state`.
