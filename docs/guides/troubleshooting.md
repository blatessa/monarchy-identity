# Troubleshooting

Start with `monarchy-identity status`, `monarchy-identity policy show` and `journalctl -t monarchy-identity`.

## A directory user is refused

- **Are they allowed?** Check `monarchy-identity policy show` against their groups in the directory. A correct password
  for someone who isn't allowed fails just like a wrong one; `journalctl -t sshd -t sddm` shows `Access denied` for a
  policy refusal and an `auth` failure for a wrong password.
- **Too many failed attempts?** The account is locked for a short time: `faillock --user NAME`, and
  `sudo faillock --user NAME --reset` to clear it.
- **First time on this laptop, and offline?** The first sign-in needs the company network.
- **Just enrolled or just rebooted?** The laptop needs a few seconds to reach the directory.
- **Clock wrong?** Sign-in fails when the clock is more than about five minutes off. Check `timedatectl`.

## Directory sign-in stopped working for everyone

```bash
sudo monarchy-identity reassert
```

It puts the sign-in configuration back and starts the directory service if it has stopped. If that reports that the
laptop needs re-enrolling, run `leave` and `enroll` again.

## `enroll` refuses

| Message contains | What to do |
|---|---|
| `say who may sign in` | Add `--groups` or `--users` (or `--mode any`). |
| `has no group named` | Check the group's name in the directory. Nothing was changed. |
| `could not search the directory` | Wrong join password, or the laptop can't reach a domain controller (DNS, network, clock). |
| `a computer account 'NAME$' already exists` | Another laptop may own that name. Pick another with `--computer-name`, or, if it's this laptop reinstalled, add `--replace-computer-account`. |
| `the generic '...'` or `longer than 15 characters` | Set a unique, short hostname, or pass `--computer-name`. |
| `already enrolled in '...'` | `--if-needed` with a different realm. Run `leave` first. |
| `accessible by group/other` | `chmod 600` the password file. |

If `enroll` fails after the join itself (for example the network dropped), fix the cause and run the same command
again; it picks up the computer account it already created.

## Getting back in

Local accounts always work. Sign in as your local account on a text console (Ctrl+Alt+F3) or over `ssh`, then
`sudo monarchy-identity leave` if you want to remove directory sign-in.
