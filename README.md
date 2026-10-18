# monarchy-identity

[![CI](https://github.com/blatessa/monarchy-identity/actions/workflows/ci.yml/badge.svg)](https://github.com/blatessa/monarchy-identity/actions/workflows/ci.yml)
[![Docs](https://github.com/blatessa/monarchy-identity/actions/workflows/docs.yml/badge.svg)](https://docs.monarchy.run/monarchy-identity/)

Directory sign-in for [Omarchy](https://omarchy.org). A small utility that connects a laptop to your company directory
and lets people sign in with their company account: at the login screen, the lock screen, a terminal, `ssh` and `sudo`.
Directories plug in as providers: Active Directory today; Entra ID, Okta, Google Workspace and FreeIPA planned.

- Nobody may sign in until you name a directory group (or users); access is managed in the directory.
- Optional `sudo` for a directory group, and offline sign-in with an optional expiry.
- Survives Omarchy updates that overwrite the sign-in configuration.
- Scriptable: unattended enrollment, and `status --json` for MDMs and other tools.

It only does sign-in. Device management (compliance, inventory, hardening) belongs to your MDM.

> **Prototype.** Only the Active Directory provider exists. It is tested against Samba AD in a VM and has been tried by hand on a real Omarchy laptop
> against a Windows Server domain (login screen, lock screen, console, `omarchy update`). See [status](docs/status.md) for what isn't covered.

## Quick start

```bash
sudo pacman -U monarchy-identity-*.pkg.tar.zst        # from a release, or from a checkout: packaging/build-local.sh -si
sudo monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser --groups laptop-users   # Active Directory
monarchy-identity status
```

## Documentation

**<https://docs.monarchy.run/monarchy-identity/>** (sources in [`docs/`](docs/)): start with
[Getting started](docs/getting-started.md). Contributors and coding agents: [AGENTS.md](AGENTS.md) and the
[development docs](docs/dev/architecture.md).

[CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) (report vulnerabilities privately) · MIT, see
[LICENSE](LICENSE).
