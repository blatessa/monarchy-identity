# Status and limits

monarchy-identity is a prototype (version 0.1.0). What's listed under "Tested" is covered by automated tests against a
Samba AD domain and an Arch virtual machine set up with Omarchy's sign-in and login-screen files. Everything else is
untested.

## Tested

- Enrolling with and without a pinned domain controller, into an OU, with a chosen computer name, over an existing
  computer account, and unattended with a password file and `--if-needed`.
- All three login policies, changing the policy without re-joining, and `sudo` for a directory group.
- Sign-in at the login screen, lock screen, terminal, `ssh` and `sudo`; refusal for people who aren't allowed.
- A wrong password, an unknown group or an unreachable domain controller stops enrollment before sign-in changes.
- Local accounts keep working when the directory service is stopped or missing.
- Cached sign-in while the domain controller is down.
- Changing a directory password with `passwd`, and handling an expired one.
- Repair after a package update overwrites the configuration; installing and removing the package.
- The login screen theme in SDDM.

## Not tested

- Windows Active Directory. This is the biggest open question.
- Omarchy's own login screen session, its lock screen and a full Hyprland session.
- A real `omarchy update`.
- The bar widget in a live Omarchy shell.
- Cached sign-in actually expiring after `--offline-days`.

## Known limits

- **Expired passwords at the login screen.** The login screen can't ask for a new password yet; change it on a text
  console or in your web portal.
- **`su`** doesn't work for directory users, and graphical admin prompts (polkit) are unchecked.
- **`sudo`** is all-or-nothing per group.
- **Group Policy logon rules and smart cards** aren't supported.

Planned work is tracked in [GitHub issues](https://github.com/blatessa/monarchy-identity/issues).
