# Status and limits

Version 0.1.0. Active Directory (Windows Server and Samba AD) is the only provider.

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

Planned work: [GitHub issues](https://github.com/blatessa/monarchy-identity/issues).
