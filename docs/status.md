# Status and limits

Version 0.1.0.

## Active Directory (supported)

Tested in the lab (Samba AD) and by hand on a Windows Server 2025 domain with a real Omarchy laptop.

Works: enrolling (interactive or unattended, into an OU, with a chosen computer name, over an existing computer
account); sign-in at the login screen, lock screen, terminal, `ssh`, `sudo` and admin prompts; all three login
policies and changing them without re-joining; `sudo` for a group; cached sign-in with the DC unreachable; `passwd`
and expired passwords at the login screen; `omarchy update` and package updates.

Limits:

- `su` doesn't work for directory users; use `sudo -iu`.
- Graphical admin prompts don't say whose password they want: admins use their own, others an administrator's.
- One person per laptop is what Omarchy assumes: the browser colour is shared, and a second person's `omarchy update`
  fails on the first one's log file.
- `sudo` is all-or-nothing per group.
- Not supported: Group Policy logon rules, smart cards. Not tested: several domain controllers, AD sites.

## Entra ID (in development)

Setup and behaviour: [Entra ID](providers/entra.md). Tested in the lab against a test tenant with himmelblau 4.0.6
(the version packaged for Omarchy).

Works: enrolling with an app registration (unattended too); sign-in at the login screen, lock screen and terminal;
MFA at the login screen (phone approval or code); groups, users and `sudo` for a group; cached sign-in offline;
`leave` and enrolling again.

Limits:

- A password Entra says must be changed is changed at the login screen only on a laptop's first sign-in, for someone
  without MFA. Otherwise they change it at myaccount.microsoft.com first (the himmelblau fixes are unreleased).
- Windows Hello PINs and security keys aren't supported.
- Password-only `ssh` is refused; MFA users give a code every time.
- `--offline-days` is refused. Offline sign-in uses the last online password; changes in Entra (password, disabled
  account, group removal, Conditional Access) reach the laptop when it's next online.
- `leave` keeps the device in Entra; delete it by the ID `leave` prints.
- himmelblau 4.0.7 starts ~20 s slower and sometimes fails to start ([findings](dev/findings.md#entra-id-himmelblau-406)).

Not tested: real laptops, Conditional Access, guest accounts, the tenant setting requiring MFA to join devices.

Planned work: [GitHub issues](https://github.com/blatessa/monarchy-identity/issues).
