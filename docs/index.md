# monarchy-identity

Directory sign-in for [Omarchy](https://omarchy.org) laptops. The login screen, lock screen, terminals, `ssh` and
`sudo` take directory accounts; only the groups or users you name may sign in.

| Provider | Status |
|---|---|
| [Active Directory](providers/ad.md) (Windows Server, Samba AD) | Supported |
| [Microsoft Entra ID](providers/entra.md) | In development |
| Okta, Google Workspace, FreeIPA | Planned |

It only changes sign-in. Device management (disk encryption, firewall, inventory, settings) is your MDM's job.

## Install

```bash
sudo pacman -S monarchy-identity
```

Until it's in Omarchy's package repository, use the file from the
[latest release](https://github.com/blatessa/monarchy-identity/releases):

```bash
sha256sum -c --ignore-missing SHA256SUMS
sudo pacman -U monarchy-identity-*.pkg.tar.zst
```

Installing changes nothing until `enroll`.

## Enroll

Prepare the directory and the laptop first: [Active Directory](providers/ad.md#prepare-the-directory),
[Entra ID](providers/entra.md#prepare-the-tenant).

```bash
# Active Directory: asks for joinuser's password
sudo monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser --groups laptop-users
# Entra ID: asks for the app registration's client secret
sudo monarchy-identity enroll entra --tenant corp.onmicrosoft.com --client-id 0f1e2d3c-... --groups linux-users
```

`enroll` checks the credentials and the group names against the directory before it changes anything, and turns off
Omarchy's autologin (`--keep-autologin` keeps it). Output ends with `enrolled in ...`.

## Check

```bash
monarchy-identity status
```

Sign in as a member of the group on a text console (Ctrl+Alt+F3) or the lock screen; after a reboot the login screen
has a username field. `su` doesn't use the directory on Arch, so it can't be used to test.

## Pages

| | |
|---|---|
| [How sign-in works](concepts/how-it-works.md) | What changes for people and for local accounts |
| [Manage laptops](guides/manage.md) | Change the policy, automate enrollment, roll out, leave, uninstall |
| [Troubleshooting](guides/troubleshooting.md) | Refused sign-ins, `enroll` errors, recovery |
| [CLI](reference/cli.md), [status --json](reference/status-output.md) | Reference |
| [Status and limits](status.md) | What's tested, what isn't |

Source and issues: <https://github.com/blatessa/monarchy-identity>. MIT licensed.
