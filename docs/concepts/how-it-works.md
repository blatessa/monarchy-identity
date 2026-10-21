# How sign-in works

An enrolled laptop asks the directory at each sign-in whether the person exists, the password is right, and they are
allowed. Accounts aren't created ahead of time: a person's account and home folder appear at their first sign-in.

## Who may sign in

Nobody, until you say. One of these is required at `enroll`:

| Option | Who |
|---|---|
| `--groups laptop-users` | Members of these directory groups (`--groups a,b` for several) |
| `--users alice,bob` | Only these people |
| `--mode any` | Everyone in the directory |

Active Directory names are short (`alice`). Entra ID takes sign-in names (`alice@corp.example.com`); a bare `alice` gets
the tenant's domain. Someone not allowed is told the account can't sign in on this laptop. Change it later with
[`policy set`](../guides/manage.md#change-who-may-sign-in).

## Where

| Where | |
|---|---|
| Login screen | Switched to a theme with a username field (Omarchy's stock theme only signs in the last user). |
| Lock screen, terminals, `ssh`, `sudo`, admin prompts | Directory password, same policy. |
| `su` | Not supported for directory users (Arch's `su` uses local passwords only). Use `sudo -iu`. |

## Offline

The first sign-in on a laptop needs the directory. After that, cached credentials work offline. `--offline-days N`
makes them expire after N days without reaching the directory (Active Directory only).

## Local accounts

Unchanged, including when the directory is unreachable or its client is broken. A local account wins over a directory
user of the same name: that directory user can't sign in on the laptop.

## Admin rights

Directory users get `sudo` only through `--sudo-groups`. Members of those groups also answer graphical admin prompts.

## Passwords

- **Active Directory:** `passwd` changes it, under the directory's rules. An expired password (or "change at next
  sign-in") gets a full-screen change screen after the login screen: current password, new one twice, then the
  desktop. Giving up returns to the login screen. Other services refuse an expired password. The screen works from the
  first restart after enrolling.
- **Entra ID:** passwords are changed with Microsoft. See [Entra ID](../providers/entra.md#how-it-behaves).

## When sign-in fails

The login screen says why:

| Situation | The login screen says |
|---|---|
| Wrong password | Wrong password. |
| A name the directory doesn't know, or a first sign-in on this laptop without the internet | No account with that name. A first sign-in on this laptop needs the internet. |
| Not allowed on this laptop, disabled, or locked out by the directory | This account can't sign in on this laptop. Ask IT. |
| The account has expired | This account has expired. Ask IT. |
| 10 wrong passwords in a row (Omarchy's lockout) | Too many wrong passwords. Try again in 2 minutes. |

A disabled or expired account only says so after the right password. Entra ID refusals show Entra's own reason.

## Autologin

`enroll` turns off Omarchy's autologin so the login screen appears; `--keep-autologin` keeps it. `leave` restores it.

## Updates

After package updates (Omarchy's included) the pacman hook re-applies the sign-in configuration.
`sudo monarchy-identity reassert` does the same by hand.
