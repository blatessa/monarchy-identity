# Troubleshooting

First: `monarchy-identity status`, `monarchy-identity policy show`, `journalctl -t monarchy-identity`.

## A directory user is refused

| Check | How |
|---|---|
| Allowed? | `policy show` against their groups. A policy refusal logs `Access denied` (`journalctl -t sshd -t sddm`); a wrong password logs an `auth` failure. |
| Locked by failed attempts? | `faillock --user NAME`; `sudo faillock --user NAME --reset` |
| First sign-in on this laptop, offline? | The first sign-in needs the directory. |
| Just enrolled or booted? | Give the directory client a few seconds. |
| Clock? | More than ~5 minutes off fails sign-in: `timedatectl`. |
| Testing with `su`? | `su` doesn't use the directory. Use a text console (Ctrl+Alt+F3), the lock screen or the login screen. |
| Right password? | People use their own directory password. `enroll` wants the join account's (Entra ID: the client secret). |

## Sign-in broke for every directory user

```bash
sudo monarchy-identity reassert
```

Re-applies the sign-in configuration and starts the directory client. If it says the laptop needs re-enrolling:
`leave`, then `enroll`.

## `enroll` refuses

| Message | Fix |
|---|---|
| `say who may sign in` | Add `--groups` or `--users`. |
| `has no group named` | Check the name in the directory. |
| `accessible by group/other` | `chmod 600` the password file. |
| Others | [Active Directory](../providers/ad.md#troubleshooting), [Entra ID](../providers/entra.md#troubleshooting) |

A refusal changes nothing. If `enroll` stops partway, fix the cause and run the same command again.

## Opening another person's home folder asks for a password

Home folders are private to their owner (mode 700).

## Getting back in

Local accounts always work: sign in as one on a text console or over `ssh`, then `sudo monarchy-identity leave` if
needed.
