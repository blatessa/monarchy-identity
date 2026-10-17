# monarchy-identity

[![CI](https://github.com/blatessa/monarchy-identity/actions/workflows/ci.yml/badge.svg)](https://github.com/blatessa/monarchy-identity/actions/workflows/ci.yml)
[![Docs](https://github.com/blatessa/monarchy-identity/actions/workflows/docs.yml/badge.svg)](https://blatessa.github.io/monarchy-identity/)

Directory sign-in for [Omarchy](https://omarchy.org). A small utility that joins a laptop to Active Directory and lets
people sign in with their company account: at the login screen, the lock screen, a terminal, `ssh` and `sudo`.

- Nobody may sign in until you name a directory group (or users); access is managed in the directory.
- Optional `sudo` for a directory group, and offline sign-in with an optional expiry.
- Survives Omarchy updates that overwrite the sign-in configuration.
- Scriptable: unattended enrollment, and `status --json` for MDMs and other tools.

It only does sign-in. Device management (compliance, inventory, hardening) belongs to your MDM.

> **Prototype.** Tested against Samba AD in a VM. Windows AD, Omarchy's own login screen and the Quickshell lock screen
> are untested.

## Quick start

```bash
sudo pacman -U monarchy-identity-*.pkg.tar.zst        # from a release, or: cd packaging && makepkg -si
sudo monarchy-identity enroll --realm CORP.EXAMPLE.COM --admin joinuser --groups laptop-users
monarchy-identity status
```

## Documentation

**<https://blatessa.github.io/monarchy-identity/>** (sources in [`docs/`](docs/)): start with
[Getting started](docs/getting-started.md). Contributors and coding agents: [AGENTS.md](AGENTS.md) and the
[development docs](docs/dev/architecture.md).

[CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) (report vulnerabilities privately) · MIT, see
[LICENSE](LICENSE).
