# How sign-in works

What changes on a laptop when it joins your directory, and what people notice.

## Terms

- **Directory**: your company's store of people, groups and passwords (Active Directory).
- **Realm**: the directory's domain name, such as `CORP.EXAMPLE.COM`. It's what you pass as `--realm`.
- **Join account**: an account allowed to add computers to the directory. It's only used while enrolling.
- **Computer account**: the laptop's own entry in the directory, named after its hostname.
- **OU** (organizational unit): a folder in the directory where laptops' computer accounts can go.

## The idea

Today an Omarchy laptop knows its users because someone created accounts on it. Once a laptop is **enrolled**, it also
asks your directory: *does this person exist, is the password right, and are they allowed on this laptop?* The
directory stays the one place where people, groups and passwords live.

Enrolling does two things:

1. **Joins** the laptop to the directory, which creates its computer account.
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

People change their directory password with `passwd` in a terminal, and the directory's password rules apply. If a
password has **expired**, the login screen can't ask for a new one yet: the person changes it on a text console
(Ctrl+Alt+F3) or in your web portal, then signs in normally.

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
