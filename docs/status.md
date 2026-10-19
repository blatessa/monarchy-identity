# Status and limits

Version 0.1.0. Active Directory (Windows Server and Samba AD) is the supported provider. Microsoft Entra ID is in
development: it works in the lab against a test tenant, and needs the himmelblau package, which isn't in Omarchy's
repository yet.

## Works

- Enrolling, interactively or unattended, into an OU, with a chosen computer name, or over an existing computer account.
- Sign-in at the login screen, lock screen, terminal, `ssh`, `sudo` and administrator prompts.
- All three login policies, and changing them without re-joining.
- `sudo` for a directory group.
- Cached sign-in while the domain controller is unreachable.
- Changing a password with `passwd`, and changing an expired password at the login screen.
- Keeping sign-in working through `omarchy update` and package updates.

## Limits

- **`su`** doesn't work for directory users. Use `sudo`, or `sudo -iu` to become another user.
- **Graphical admin prompts** don't say whose password they want: people in the admin group use their own, anyone
  else an administrator's.
- **One person per laptop** is what Omarchy is built for: the browser colour is shared, and a second person's
  `omarchy update` fails on the first one's log file.
- **`sudo`** is all-or-nothing per group.
- **Not supported:** Group Policy logon rules and smart cards. Domains with several controllers or AD sites haven't
  been tested.

## Entra ID (in development)

Works in the lab: enrolling with an app registration (unattended too), password sign-in at the login screen, lock
screen and terminal, allowing groups or people, `sudo` for a group, cached sign-in with no network, and leaving.

- **Authenticator codes.** Where Entra asks for one (a person's first sign-in on a laptop, and when it wants MFA again),
  the login screen takes the password and a screen before the desktop asks for the code. Approval on the phone
  hasn't been tested, and Windows Hello PINs aren't there yet.
- **`ssh` with only a password is refused** by the Entra client for remote sign-in; with MFA it asks for the code
  every time.
- **`--offline-days`** can't be honoured: Entra's client has no limit for its offline cache.
- **Offline sign-in uses the password from the last online sign-in.** Until the laptop is online again, a password
  changed or reset in Entra isn't known to it (the old one still works), and disabling an account, removing it from
  the allowed groups or a Conditional Access policy doesn't reach it. Someone who never signed in on the laptop can't
  sign in offline.
- **Leaving** keeps the laptop's device record in Entra; delete it in the Entra admin center (`leave` prints its device
  ID). Enrolling a reinstalled laptop registers a new device with the same name next to the old one.

Planned work: [GitHub issues](https://github.com/blatessa/monarchy-identity/issues).
