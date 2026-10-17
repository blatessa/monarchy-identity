# monarchy-identity

Company sign-in for [Omarchy](https://omarchy.org) laptops. People sign in with the account they already have in your
company directory, and you decide who may sign in on which laptops.

Directories plug in as [providers](providers/index.md). Active Directory is available today; Microsoft Entra ID, Okta,
Google Workspace and FreeIPA are planned.

It does one job: connect a laptop's sign-in to your directory. It's a small package you install and run yourself, or
call from your MDM or configuration management.

!!! warning "Prototype"
    Only the Active Directory provider exists, tested against Samba AD in a virtual machine. Omarchy's own login screen
    and lock screen, and real `omarchy update` runs, are not tested yet. See [Status and limits](status.md).

## What it does

- **One account everywhere.** People sign in at the login screen, the lock screen, a terminal, `ssh` and `sudo` with
  their company credentials. Nobody creates accounts on laptops by hand.
- **You choose who gets in.** Nobody may sign in until you name a directory group (or a list of people). Add or remove
  people in the directory and every laptop follows.
- **Optional admin rights.** Give a directory group `sudo` on its laptops.
- **Survives updates.** If an Omarchy update overwrites the sign-in configuration, it's put back after the update.
- **Scriptable.** Every command works unattended, and `status --json` tells your tooling what state a laptop is in.

## What it doesn't do

It doesn't manage the laptop: no disk-encryption or firewall checks, no inventory, no removing admin rights from
existing local users, no locking down settings. Use your MDM for those.

## Where to start

| You want to | Read |
|---|---|
| Try it on one laptop | [Getting started](getting-started.md) |
| See which directories work | [Providers](providers/index.md) |
| Understand what changes for people | [How sign-in works](concepts/how-it-works.md) |
| Plan a fleet rollout | [Roll out to a fleet](guides/rollout.md) |
| Script enrollment | [Automate enrollment](guides/automation.md) |
| Look up a command | [CLI reference](reference/cli.md) |
| Fix a problem | [Troubleshooting](guides/troubleshooting.md) |

Source and issues: <https://github.com/blatessa/monarchy-identity>. MIT licensed.
