# Safety model

The risk is a PAM or nsswitch mistake that stops people signing in. The design assumes that will be attempted and
limits the damage.

## Principles

- **Default deny.** No mode admits the whole directory unless `--mode any` is given.
- **Local accounts first.** The `pam_sss` rules fall through to `pam_unix` for any user sssd does not know.
- **Fail closed for the directory, open for local users.** With sssd stopped, directory users are refused (about
  three seconds in the lab) and local users are unaffected. With `pam_sss.so` removed, directory users are refused
  and local users are unaffected.
- **Enforcement is root-owned.** The policy lives in `/etc`. The shell widget is a display, not a boundary.
- **Verify before PAM.** `enroll` confirms the directory works (keytab authenticates, sssd online, the group
  resolves) before the first PAM edit.
- **Failure leaves nothing behind.** A failed `enroll` restores the machine and deletes the computer account it
  created.

## Guards on `enroll`

| Guard | Behaviour |
|---|---|
| Local fallback | Refused unless a local account with uid 1000-59999, a real shell and a usable password hash exists. Override: `--allow-no-local-fallback`. |
| Computer account | An existing account of the same name is never taken over; `--replace-computer-account` is required. |
| Hostname | Generic names and names over 15 characters are refused. |
| Input | Realm, server, admin, groups, users, OU and numbers are validated before they reach `sssd.conf`, `smb.conf`, `krb5.conf` or sudoers. |
| Auto-revert | `--confirm-within N` runs `leave` after N minutes unless `monarchy-identity confirm` is run. |
| Credentials | The join password comes from stdin or a file that is a regular file, not a symlink, owned by root or the caller, with no group or other permissions. It is never put on a command line. |

## Behaviour under failure

Observed in the lab:

| Situation | Local users | Directory users |
|---|---|---|
| sssd stopped | unaffected (sudo, login, SDDM, SSH) | refused quickly |
| `pam_sss.so` missing | unaffected | refused |
| Domain controller unreachable | unaffected | cached users can sign in; never-seen users cannot |
| Enrolment fails partway | machine and directory unchanged | not applicable |
| Package removed while enrolled | `pre_remove` runs `leave` first | not applicable |
| Many rapid policy changes | sssd is not left in systemd's `start-limit-hit` state | not applicable |

If a machine misbehaves, switch to a text console (Ctrl+Alt+F3), sign in as the local fallback account and run
`sudo monarchy-identity leave`.
