# monarchy-identity

[![CI](https://github.com/blatessa/monarchy-identity/actions/workflows/ci.yml/badge.svg)](https://github.com/blatessa/monarchy-identity/actions/workflows/ci.yml)
[![Docs](https://github.com/blatessa/monarchy-identity/actions/workflows/docs.yml/badge.svg)](https://blatessa.github.io/monarchy-identity/)

Directory sign-in, login policy and posture reporting for [Omarchy](https://omarchy.org). It is the identity
component of Monarchy, a set of tools for running Omarchy as a work computer.

- Joins a laptop to Active Directory or Samba AD and adds `pam_sss` to the login, lock-screen, `sudo` and `sshd`
  PAM stacks without changing how local accounts authenticate.
- Enforces a default-deny login policy: members of listed groups, listed users, or the whole directory.
- Selects an SDDM theme with a username field (Omarchy's stock theme logs in only the last user).
- Repairs its own configuration within seconds if an update or a person overwrites it.
- Reports posture as JSON (`status --json`) and evaluates it against a policy file (`check`).

> **Prototype.** Verified in a VM against Samba AD. Windows AD, FreeIPA, Entra ID, Omarchy's own login screen and the
> Quickshell lock screen are untested. Pilot on machines you can recover.

## Quick start

```bash
sudo pacman -U monarchy-identity-*.pkg.tar.zst        # from a release, or: cd packaging && makepkg -si

sudo monarchy-identity enroll sssd --realm CORP.EXAMPLE.COM --admin joinuser \
  --ou 'OU=Laptops,DC=corp,DC=example,DC=com' \
  --mode groups --groups laptop-users --disable-autologin --confirm-within 10

monarchy-identity status                               # check, sign in as a directory user, then:
sudo monarchy-identity confirm                         # otherwise the machine reverts itself in 10 minutes
```

The hostname must be unique and at most 15 characters, and a local account with a password must exist as a fallback.

## Documentation

Full documentation: **<https://blatessa.github.io/monarchy-identity/>** (sources in [`docs/`](docs/)).

| | |
|---|---|
| [Getting started](docs/getting-started.md) | Prerequisites, install, enrol, verify |
| [Plan a rollout](docs/guides/rollout-planning.md), [Automate enrolment](docs/guides/automation.md) | Fleet deployment |
| [CLI](docs/reference/cli.md), [Posture report](docs/reference/posture.md), [Policy file](docs/reference/policy-file.md) | Reference |
| [Evidence from the lab](docs/evidence.md) | Captured proof of directory authentication |
| [AGENTS.md](AGENTS.md), [Testing](docs/dev/testing.md) | Contributors and coding agents |

Open work is tracked in [GitHub issues](https://github.com/blatessa/monarchy-identity/issues).
[CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) (report vulnerabilities privately) · MIT, see
[LICENSE](LICENSE).
