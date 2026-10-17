# Staying safe

Changing how a laptop authenticates is the riskiest thing an admin tool can do: a mistake means nobody can sign in.
monarchy-identity is built around not letting that happen, and around undoing itself when it does.

## The safeguards

| Safeguard | What it does |
|---|---|
| **Local accounts always work** | The directory is consulted *in addition to* local accounts. A stopped service, a broken configuration or a missing component can't stop a local user signing in. Enrollment refuses unless a local account with a password exists. |
| **Nothing changes until it's proven** | `enroll` checks that the laptop can really authenticate to the directory and find your group *before* it edits any sign-in configuration. |
| **Failure undoes itself** | If enrollment fails at any point, the laptop is restored and the computer account it created is deleted. |
| **A safety timer** | Enrolling at a terminal starts a 10-minute timer; unless you run `sudo monarchy-identity confirm` the laptop leaves the domain by itself. You confirm only after seeing a directory sign-in work. |
| **Computer accounts aren't taken over** | If the name already exists in the directory, `enroll` stops rather than resetting another laptop's account. |
| **Deny by default** | Nobody can sign in unless you name a group or users. |
| **Admin input is checked** | Names, groups and settings are validated before they reach any configuration file, and the join password is never put on a command line or stored. |

## What happens when things break

Observed in testing:

| Situation | Local users | Directory users |
|---|---|---|
| The sign-in service (sssd) is stopped | Unaffected | Refused quickly |
| A required component is missing | Unaffected | Refused |
| The domain controller is unreachable | Unaffected | Anyone who signed in before can still sign in; new people can't |
| Enrollment fails halfway | Machine and directory unchanged | n/a |
| The package is removed while enrolled | It unenrolls the laptop first | n/a |

## If a laptop misbehaves

Switch to a text console (Ctrl+Alt+F3), sign in with the local account, and run:

```bash
sudo monarchy-identity leave --admin JOINACCOUNT
```

That restores the laptop to how it was before enrolling. (`--admin` also deletes its computer account; without it the
account stays in the directory until you remove it.)

The safeguards you can adjust (and why you rarely should) are in the [CLI reference](../reference/cli.md).
