# How sign-in works

## The idea

Once a laptop is **enrolled**, it asks your directory whenever someone signs in: *does this person exist, is the
password right, and are they allowed on this laptop?* The directory stays the one place where people, groups and
passwords live. Enrolling registers the laptop with the directory (in Active Directory, a computer account) and connects
its sign-in, alongside the local accounts it already has. Nothing is created per person in advance: a person's account
appears on a laptop the first time they sign in.

## Where people sign in

| Where | What happens |
|---|---|
| **Login screen** | Omarchy's stock login screen only signs in whoever used it last, so enrolling switches to a theme with a username box. It looks like Omarchy's, with one extra line, and remembers the last user. `--keep-login-theme` keeps the stock screen; directory users then can't sign in there. |
| **Lock screen** | Unlocks with the directory password. |
| **Terminals, `ssh`, `sudo`** | Same password, same rules. |

Someone who isn't allowed gets the same result as a wrong password.

## First sign-in and working offline

The **first** sign-in on a laptop needs the company network: that's when the laptop learns who the person is and creates
their home folder, which is private to them. Later sign-ins work offline, from a protected cached copy of the
credentials. You can make that copy expire after some days away (`--offline-days`).

## Local accounts

Local accounts, including the one the laptop was set up with, keep working exactly as before, also when the directory
can't be reached. The rules on these pages don't apply to them.

## Passwords

People change their directory password with `passwd` in a terminal, and the directory's password rules apply.

If a password has **expired** (or you set "change at next sign-in"), the person signs in at the login screen as usual
and gets a full-screen "Your password has expired" screen before the desktop. They type the current password, then the
new one twice; the directory's own messages ("too short", "used before") appear there. Once it's changed, the desktop
starts; if they give up, they're back at the login screen. Nothing else (the lock screen, `ssh`, `sudo`) lets an
expired password in. The screen works from the first restart after enrolling.

## Admin rights

Signing in doesn't make someone an administrator. Directory users get `sudo` only if you name their group with
`--sudo-groups`. Local users keep whatever rights they had.

## Autologin

Omarchy signs the first user in automatically once the disk is unlocked. On a laptop people sign in to with their own
account, that would skip the login screen, so enrolling turns autologin off. `--keep-autologin` keeps it, and `leave`
turns it back on.

## Updates

Omarchy updates sometimes overwrite the sign-in configuration. monarchy-identity puts its part back after every package
update, and after its own upgrades, so directory sign-in keeps working with nothing to set up.
`sudo monarchy-identity reassert` repairs it by hand, and is safe to run any time.
