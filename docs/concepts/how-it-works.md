# How sign-in works on Omarchy

This page explains what changes on a laptop when it joins your directory, and what people will notice. You don't
need to know how Active Directory or Linux authentication work internally; the [reference](../reference/enrollment-steps.md)
has those details if you want them.

## Terms

- **Directory**: your company's store of people, groups and passwords (Active Directory).
- **Realm**: the directory's domain name, such as `CORP.EXAMPLE.COM`. It is what you pass as `--realm`.
- **Join account**: an account allowed to add computers to the directory. It's only used while enrolling.
- **Computer account**: the laptop's own entry in the directory, named after its hostname.
- **OU** (organizational unit): a folder in the directory; laptops' computer accounts can be placed in one.

## The idea

Today an Omarchy laptop knows its users because someone created accounts on it. Once a laptop is **enrolled**, it also
asks your company directory: *does this person exist, is the password right, and are they allowed on this machine?*
The directory stays the single place where people, groups and passwords live. Adding someone to the right group is
all it takes for them to sign in on every enrolled laptop; removing them takes access away.

Enrolling does two things:

1. **Joins** the laptop to the directory, which creates a *computer account* for it (named after its hostname).
2. **Teaches the laptop's sign-in** to consult the directory, next to the local accounts it already has.

Nothing is created per person in advance. A directory user's account appears on a laptop the first time they sign in.

## Where people sign in

All of these use the same company username and password:

| Where | What happens |
|---|---|
| **The login screen** | Omarchy's stock screen only logs in whoever used it last, so enrolling switches it to a theme with a username box. It looks like Omarchy's, with one extra line. The last user is remembered and pre-filled. |
| **The lock screen** | Unlocking uses the directory password too. |
| **Terminals, `ssh` and `sudo`** | Same password, same policy. |

A person who isn't allowed gets the same red "didn't work" screen as a typo. The screen deliberately doesn't say why.

## The first sign-in, and working offline

The **first** sign-in on a laptop needs the company network: that's when the laptop learns the person and creates their
home directory (`/home/<username>`, private to them). This takes a few seconds longer than later sign-ins.

After that, the laptop remembers a protected copy of the credentials, so the person can sign in with no network. You
can limit this (for example, require reconnecting after 14 days away); see [Change who may sign in](../guides/change-policy.md).
A person the laptop has never seen can't sign in offline.

## Local accounts keep working

Local accounts, including the one you set up the laptop with, are untouched. If the directory is unreachable, sssd is
stopped, or something is misconfigured, local users still sign in. Enrollment refuses to proceed unless a local account
with a password exists, because that account is your way back in. See [Staying safe](safety-model.md).

## Passwords

People change their directory password with `passwd` in a terminal, and the directory's password rules apply. If a
password has **expired**, the graphical login screen can't ask for a new one (it just fails). The person changes it in
your web portal, or on a text console (Ctrl+Alt+F3), then signs in normally. This is a known limit; see
[Status and limits](../status.md).

## Admin rights

Signing in does **not** make someone an administrator. By default directory users have no `sudo`. You can map a
directory group to `sudo` (`--sudo-groups`), but if you manage privileges with an MDM, leave that to the MDM; this tool
doesn't remove admin rights from existing local users either.

## Disk encryption and autologin

Omarchy encrypts the disk and, by default, **signs the first user in automatically** at boot: the disk passphrase is the
login. That is fine for one person's laptop, but on a laptop that people sign in to with their own company account it
would hide the login screen. So enrolling **turns autologin off** by default and the login screen appears at boot.
`--keep-autologin` keeps Omarchy's behaviour. `monarchy-identity status` always shows whether autologin is on, and `leave`
restores the previous setting.

## What changes on the laptop

Enrolling edits the sign-in configuration (the PAM stacks for the login screen, lock screen, `sudo`, terminals and
`ssh`), adds the directory to the system's user lookup, writes the directory-join configuration, selects the login
theme, and installs a watcher that undoes outside changes. Every original file is backed up, and `leave` puts everything
back exactly. The edits are written so that a broken directory connection can't affect local users. Details:
[Staying correct](self-healing.md) and [what enroll does, step by step](../reference/enrollment-steps.md).
