# monarchy-identity

Company sign-in for [Omarchy](https://omarchy.org) laptops. People use the username and password they already have in
your directory (Active Directory, today); you decide who may sign in on which laptops, and you can check the state of
every machine.

It is the identity part of **Monarchy**, a set of tools for running Omarchy as a work computer.

!!! warning "Prototype"
    Tested against Samba AD in a virtual machine. Windows Active Directory, Omarchy's own login screen and lock screen,
    and real `omarchy update` runs are not tested yet. See [Status and limits](status.md) and pilot on machines you can
    recover.

## What you get

- **One account everywhere.** A person signs in at the Omarchy login screen, lock screen, a terminal or `ssh` with their
  company credentials. Nobody creates accounts on laptops by hand.
- **Access you control.** Nobody may sign in until you name a group (or users). Add or remove people in the directory.
- **Safe by design.** Local accounts keep working whatever happens to the directory, a failed enrollment undoes itself,
  and a safety timer reverts a bad first enrollment. See [Staying safe](concepts/safety-model.md).
- **Stays working.** If something overwrites the configuration, a watcher repairs it within seconds (proven by simulated
  overwrites and package upgrades; a real `omarchy update` hasn't been exercised yet).
- **A fleet view.** Every laptop reports its identity and security posture as JSON, and one command checks it against
  your own definition of healthy.

## What it leaves to you

It doesn't remove admin rights from existing users, manage `sudo` beyond an optional group, harden boot, or keep a
fleet inventory. Use your MDM or configuration management for those; this tool reports on them.

## Where to start

| You want to | Read |
|---|---|
| Understand what changes on a laptop | [How sign-in works on Omarchy](concepts/how-it-works.md) |
| Plan a fleet rollout | [Roll out to a fleet](guides/rollout.md) |
| Enroll your first laptop | [Getting started](getting-started.md) |
| Script enrollment | [Automate enrollment](guides/automation.md) |
| Look up a command or option | [CLI reference](reference/cli.md) |
| Fix a problem | [Troubleshooting](guides/troubleshooting.md) |

Source and issues: <https://github.com/blatessa/monarchy-identity>. MIT licensed.
