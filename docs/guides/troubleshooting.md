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
- **Testing with `su`?** On Arch, `su` never asks the directory. Test on a text console (Ctrl+Alt+F3), the lock screen
  or the login screen.
- **Which password?** People sign in with their own directory password. `enroll` asks for the join account's directory
  password, and `sudo` for your own.

## Opening someone's home folder asks for a password

Each person's home folder is private to them. Your file manager asks for your password to open another person's,
as an administrator. That's expected.

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
| `accessible by group/other` | `chmod 600` the password file. |

Anything else is specific to your directory: see the provider page's troubleshooting, for example
[Active Directory](../providers/ad.md#troubleshooting). If `enroll` stops partway (for example the network dropped),
fix the cause and run the same command again.

## Getting back in

Local accounts always work. Sign in as your local account on a text console (Ctrl+Alt+F3) or over `ssh`, then
`sudo monarchy-identity leave` if you want to remove directory sign-in.
