# Troubleshooting

Start with `monarchy-identity status`, `sudo monarchy-identity policy show` and `journalctl -t monarchy-identity`.

## A directory user is refused

- Check the policy and the user's group membership: `sudo monarchy-identity policy show`,
  `sudo sssctl user-checks USER </dev/null`.
- Look at the service's log: `journalctl -t sshd -t sddm`. `pam_sss(...:account): Access denied ... Permission denied`
  means the policy refused a correct password. A wrong password shows as an `auth` failure.
- Faillock applies to directory users as well. After repeated failures the account is locked for a short time
  (`faillock --user USER`, `faillock --user USER --reset`).
- A user never seen on this machine cannot sign in while the domain controller is unreachable.
- sssd needs a few seconds to reach the DC after a restart.

## Everything fails after a time change or resume

Check the clock. `status` shows `time sync`; Kerberos fails beyond about five minutes of skew.

## sssd is in a failed state

```bash
sudo systemctl reset-failed sssd && sudo monarchy-identity reassert
```

Rapid restarts hit systemd's start limit; monarchy-identity's own commands reset it before restarting.

## `enroll` refuses

| Message contains | Cause and fix |
|---|---|
| `a computer account 'NAME$' already exists` | See [Enrol safely](enrol-safely.md): `--computer-name` or `--replace-computer-account`. |
| `the generic '...'` | Set a unique hostname or pass `--computer-name`. |
| `longer than 15 characters` | Shorten the hostname or pass `--computer-name`. |
| `no local account with a usable password exists` | Create a local user with a password (or `--allow-no-local-fallback`, not recommended). |
| `group '...' not resolvable via sssd; refusing to modify PAM` | The group name is wrong, the DC is unreachable, or the join account cannot read it. Nothing was changed. |
| `already enrolled in '...'` | You used `--if-needed` with a different realm. Run `leave` first. |
| `password file ... accessible by group/other` | `chmod 600` it. |

## `monarchy-identity check` exits 2

Read the message: it names the file and line (`unknown policy key`, `must be true or false`, ...). See
[Compliance policy file](../reference/policy-file.md).

## A command hangs or says another is running

State-changing commands take `/run/monarchy-identity.lock`. Look for a stale root process holding it by PID
(`ps`) rather than killing by name. Never run `sssctl` without `</dev/null`: when sssd is down it prompts on a
terminal and waits.

## Last resort

From a text console or SSH as the local fallback account: `sudo monarchy-identity leave`.
