# monarchy-identity

Company sign-in for [Omarchy](https://omarchy.org) laptops. People sign in with the account they already have in your
company directory, and you decide who may sign in.

- **One account everywhere.** The login screen, the lock screen, a terminal, `ssh` and `sudo` all take the company
  password. Nobody creates accounts on laptops by hand.
- **You choose who gets in.** Nobody may sign in until you name a directory group (or a list of people). Add or remove
  people in the directory and every laptop follows.
- **Optional admin rights** for a directory group.
- **Survives Omarchy updates**, and works offline once someone has signed in.
- **Scriptable.** Every command runs unattended, and `status --json` tells your tooling what state a laptop is in.

It does one job: connect a laptop's sign-in to your directory. It doesn't manage the laptop (disk encryption, firewall,
inventory, locking down settings); that's your MDM's job.

## Providers

Each kind of directory is supported by a provider. **Active Directory** (including Samba AD) is the only provider
today; Microsoft Entra ID, Okta, Google Workspace and FreeIPA are planned. Who may sign in, `sudo`, offline sign-in, the
login screen and updates work the same whichever provider you use. See [Status and limits](status.md).

## Where to start

| You want to | Read |
|---|---|
| Try it on one laptop | [Getting started](getting-started.md) |
| Understand what changes for people | [How sign-in works](concepts/how-it-works.md) |
| Plan a fleet rollout | [Roll out to a fleet](guides/rollout.md) |
| Look up a command | [CLI reference](reference/cli.md) |
| Fix a problem | [Troubleshooting](guides/troubleshooting.md) |

Source and issues: <https://github.com/blatessa/monarchy-identity>. MIT licensed.
