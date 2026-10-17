# monarchy-identity

[![CI](https://github.com/blatessa/monarchy-identity/actions/workflows/ci.yml/badge.svg)](https://github.com/blatessa/monarchy-identity/actions/workflows/ci.yml)
[![Docs](https://github.com/blatessa/monarchy-identity/actions/workflows/docs.yml/badge.svg)](https://blatessa.github.io/monarchy-identity/)

Directory sign-in, login policy and posture reporting for [Omarchy](https://omarchy.org). It is the identity
component of Monarchy, a set of tools for running Omarchy as a work computer.

- People sign in at the Omarchy login screen, lock screen, a terminal or `ssh` with their company username and password.
- Nobody may sign in until you name a group (or users): access is granted and removed in the directory.
- Local accounts always keep working, a failed enrollment undoes itself, and a first enrollment reverts on its own
  unless you confirm it.
- Omarchy updates that overwrite the configuration are repaired within seconds.
- Each laptop reports its identity and security posture as JSON, and `check` evaluates it against your own policy.

> **Prototype.** Tested against Samba AD in a VM. Windows AD, Omarchy's own login screen and the Quickshell lock screen
> are untested. Pilot on machines you can recover.

## Quick start

```bash
sudo pacman -U monarchy-identity-*.pkg.tar.zst        # from a release, or: cd packaging && makepkg -si

sudo monarchy-identity enroll --realm CORP.EXAMPLE.COM --admin joinuser \
  --ou 'OU=Laptops,DC=corp,DC=example,DC=com' \
  --groups laptop-users

monarchy-identity status                               # check, sign in as a directory user, then:
sudo monarchy-identity confirm                         # otherwise the machine reverts itself in 10 minutes
```

The hostname must be unique and at most 15 characters, and a local account with a password must exist as a fallback.

## Documentation

Full documentation: **<https://blatessa.github.io/monarchy-identity/>** (sources in [`docs/`](docs/)).

| | |
|---|---|
| [How sign-in works on Omarchy](docs/concepts/how-it-works.md) | What changes on a laptop |
| [Roll out to a fleet](docs/guides/rollout.md) | The end-to-end plan |
| [Getting started](docs/getting-started.md) | Enroll your first laptop |
| [Automate enrollment](docs/guides/automation.md) | MDM, Ansible, scripts |
| [CLI](docs/reference/cli.md), [Posture report](docs/reference/posture.md), [Policy file](docs/reference/policy-file.md) | Reference |
| [AGENTS.md](AGENTS.md), [Testing](docs/dev/testing.md) | Contributors and coding agents |

Open work is tracked in [GitHub issues](https://github.com/blatessa/monarchy-identity/issues).
[CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) (report vulnerabilities privately) · MIT, see
[LICENSE](LICENSE).
