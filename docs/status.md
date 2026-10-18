# Status and limits

monarchy-identity is a prototype (version 0.1.0). What's listed under "Tested" is covered by automated tests against a
Samba AD domain and an Arch virtual machine set up with Omarchy's sign-in and login-screen files. "Tried by hand" is what
has been checked on a real Omarchy laptop against a Windows Server domain. Everything else is untested.

## Tested

Only the Active Directory provider exists so far. With it:

- Enrolling with and without a pinned domain controller, into an OU, with a chosen computer name, over an existing
  computer account, and unattended with a password file and `--if-needed`.
- All three login policies, changing the policy without re-joining, and `sudo` for a directory group.
- Answering an administrator prompt with a directory admin's own password (as a text prompt; Omarchy's graphical one
  is below).
- Sign-in at the login screen, lock screen, terminal, `ssh` and `sudo`; refusal for people who aren't allowed.
- A wrong password, an unknown group or an unreachable domain controller stops enrollment before sign-in changes.
- Local accounts keep working when the directory service is stopped or missing.
- Cached sign-in while the domain controller is down.
- Changing a directory password with `passwd`, and handling an expired one.
- Repair after a package update overwrites the configuration; installing and removing the package.
- The login screen theme in SDDM.

## Tried by hand on real hardware

On an Omarchy laptop enrolled in a Windows Server 2025 domain (one domain controller, Windows DNS):

- Enrolling, with the domain's short (NetBIOS) name different from the first part of its DNS name.
- Signing in at Omarchy's login screen, on a text console and at the lock screen, as people in the allowed group.
- `sudo` for the people in the admin group and not for anyone else; someone outside the allowed group is refused.
- Running `omarchy update`: sign-in kept working.

## Not tested

- The automated lab suites against a Windows domain controller (only tried by hand so far), and domains with several
  controllers or sites.
- Every other directory: Microsoft Entra ID, Okta, Google Workspace and FreeIPA providers aren't written yet.
- The bar widget in a live Omarchy shell.
- Cached sign-in actually expiring after `--offline-days`.

## Known limits

- **Expired passwords at the login screen.** The login screen can't ask for a new password yet; change it on a text
  console or in your web portal.
- **`su`** doesn't work for directory users on Arch (it never asks the directory). Use `sudo`, or `sudo -iu` to
  become another user.
- **Graphical admin prompts.** People in the admin group are accepted as administrators, but Omarchy's prompt asks for
  the first local administrator's password and gives no way to choose another account
  ([#34](https://github.com/blatessa/monarchy-identity/issues/34)).
- **Omarchy is built for one person per laptop.** The browser colour is one setting for the whole machine, and the
  second person to run `omarchy update` fails because the first one's log file is in the way. Both are Omarchy's.
- **`sudo`** is all-or-nothing per group.
- **Group Policy logon rules and smart cards** aren't supported.

Planned work is tracked in [GitHub issues](https://github.com/blatessa/monarchy-identity/issues).
