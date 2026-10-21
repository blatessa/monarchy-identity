# monarchy-identity

[![CI](https://github.com/blatessa/monarchy-identity/actions/workflows/ci.yml/badge.svg)](https://github.com/blatessa/monarchy-identity/actions/workflows/ci.yml)
[![Docs](https://github.com/blatessa/monarchy-identity/actions/workflows/docs.yml/badge.svg)](https://docs.monarchy.run/monarchy-identity/)

Company directory sign-in for [Omarchy](https://omarchy.org). People sign in with their company account at the login
screen, the lock screen, a terminal, `ssh` and `sudo`, and you decide in the directory who may.

- Nobody may sign in until you name a directory group (or users).
- Optional `sudo` for a directory group, and offline sign-in with an optional expiry.
- Keeps working through Omarchy updates.
- Scriptable: unattended enrollment, and `status --json` for MDMs and other tools.

Active Directory (Windows Server and Samba AD) is supported; Microsoft Entra ID is in development; Okta, Google
Workspace and FreeIPA are planned. It only does sign-in: device management belongs to your MDM.

## Quick start

```bash
sudo pacman -S monarchy-identity
sudo monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser --groups laptop-users
monarchy-identity status
```

Until the package is in Omarchy's package repository, install the file from the
[latest release](https://github.com/blatessa/monarchy-identity/releases) with `sudo pacman -U`.

## Documentation

**<https://docs.monarchy.run/monarchy-identity/>**

Contributing: [CONTRIBUTING.md](CONTRIBUTING.md). Security: [SECURITY.md](SECURITY.md). MIT licensed.
