# Status and limits

monarchy-identity is a prototype (version 0.1.0). Behaviour listed under "Verified" is covered by automated suites
in our test environment; everything else is untested.

## Verified

Against Samba AD in testing (Arch VM with Omarchy's PAM and SDDM files as fixtures):

- Enrollment with and without `--server` (DNS SRV discovery), `--ou`, `--computer-name`, `--replace-computer-account`,
  `--sudo-groups`, `--offline-days`, `--password-file`, `--if-needed`, `--confirm-within`.
- All three login modes, `policy set` without re-joining, and sign-in through `sddm`, `sudo`, `login`, `sshd`,
  `system-remote-login` and the lock-screen PAM service.
- Rollback on a failed enrollment, leaving the machine and the directory unchanged.
- Local accounts keep working with sssd stopped and with `pam_sss.so` missing.
- Cached sign-in with the domain controller down; recovery when it returns.
- Password change and expired-password handling with `passwd`.
- Drift repair by the path unit and the pacman hook; the real package installing, removing and unwinding.
- The real SDDM greeter (X11), driven with typed keys, with the `monarchy-identity` theme.

## Not tested

- Windows Active Directory (LDAP signing, channel binding, GPO, SPN and UPN behaviour). This is the largest
  untested assumption.
- Omarchy's own greeter (SDDM inside Hyprland), the Quickshell lock screen and a graphical Hyprland session.
- A real `omarchy update` run against the self-heal mechanisms.
- FreeIPA and generic LDAP; Entra ID and other OIDC providers (not implemented).
- The status widget in a live Omarchy shell.
- Expiry of cached credentials over real time (`--offline-days` configuration is validated; expiry is not
  time-tested).

## Known limits

- **Password change at the login screen.** An expired or must-change password is refused with "new authentication
  token required". `passwd` over a text console or SSH can prompt for a new one; the graphical login screen has no
  change-password step.
- **`su`.** It uses `pam_unix` directly, so directory users cannot `su`. Omarchy has no `polkit-1` PAM service (it falls
  back to `other`); polkit authentication as a directory user is unchecked.
- **Sudo mapping** is whole-group, all commands.
- **GPO access control and smart cards** are not handled.
- **Configuration** mixes administrator intent and enrollment state in one file.
- **Join quirk.** A new computer account is joined twice; the cause is not understood ([Findings](dev/findings.md)).

Open work is tracked in the repository's
[GitHub issues](https://github.com/blatessa/monarchy-identity/issues).
