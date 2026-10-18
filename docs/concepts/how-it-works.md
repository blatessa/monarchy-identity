# How sign-in works

What changes on a laptop when it connects to your directory, and what people notice.

## Terms

- **Directory**: your company's store of people, groups and passwords: Active Directory, Microsoft Entra ID, Okta,
  Google Workspace, FreeIPA and so on.
- **Provider**: the part of monarchy-identity that talks to one kind of directory. See [Providers](../providers/index.md).
- **Enroll**: connect a laptop to the directory. What that creates in the directory depends on the provider (in Active
  Directory, a computer account for the laptop).

## The idea

Today an Omarchy laptop knows its users because someone created accounts on it. Once a laptop is **enrolled**, it also
asks your directory: *does this person exist, is the password right, and are they allowed on this laptop?* The
directory stays the one place where people, groups and passwords live.

Enrolling does two things:

1. **Registers** the laptop with the directory, in whatever way that directory expects.
2. **Connects the laptop's sign-in** to the directory, alongside the local accounts it already has.

Nothing is created per person in advance. A person's account appears on a laptop the first time they sign in.

## Where people sign in

| Where | What happens |
|---|---|
| **Login screen** | Omarchy's stock login screen only signs in whoever used it last, so enrolling switches to a theme with a username box. It looks like Omarchy's, with one extra line, and remembers the last user. |
| **Lock screen** | Unlocks with the directory password. |
| **Terminals, `ssh`, `sudo`** | Same password, same rules. |

Someone who isn't allowed gets the same "didn't work" result as a typo. The screen doesn't say why.

## First sign-in and working offline

The **first** sign-in on a laptop needs the company network: that's when the laptop learns who the person is and creates
their home folder. Later sign-ins work offline, from a protected cached copy of the credentials. You can make that copy
expire after some days away; see [Change who may sign in](../guides/change-policy.md).

## Local accounts

Local accounts, including the one the laptop was set up with, keep working exactly as before, including when the
directory is unreachable or the directory service on the laptop is stopped. The rules on this page don't apply to them.

## Passwords

People change their directory password with `passwd` in a terminal, and the directory's password rules apply.

If a password has **expired** (or you set "change at next sign-in"), the person signs in at the login screen with it as
usual and gets a full-screen "Your password has expired" screen before the desktop. They type the current password,
then the new one twice; the directory's own messages ("too short", "used before") appear there. Once it's changed, the
desktop starts. If they give up, they're back at the login screen. Nothing else (the lock screen, `ssh`, `sudo`) lets an
expired password in. The screen appears after the first restart following `enroll`.

## Admin rights

Signing in doesn't make someone an administrator. Directory users have no `sudo` unless you give a directory group
`sudo` with `--sudo-groups`. Local users keep whatever rights they had.

## Autologin

Omarchy encrypts the disk and, by default, signs the first user in automatically after the disk is unlocked. On a laptop
that people sign in to with their own account, that would skip the login screen, so enrolling turns autologin off.
`--keep-autologin` keeps Omarchy's behaviour. `leave` turns it back on.

## Updates

Omarchy updates sometimes overwrite the sign-in configuration. monarchy-identity puts its part back after every package
update, so directory sign-in keeps working. See [Omarchy integration](../guides/omarchy-integration.md#updates).
