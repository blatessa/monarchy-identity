# Omarchy integration

How enrollment fits the parts of Omarchy people see, and the updates that happen underneath.

## Login screen

Omarchy's stock login screen signs in whoever used it last and has no username box. Enrollment switches to the
`monarchy-identity` theme: Omarchy's own look plus a username line. It uses Omarchy's artwork, so it keeps matching.

`--keep-login-theme` keeps the stock screen; directory users then can't sign in there (terminals and `ssh` still work).

## Lock screen

Directory users unlock with their directory password.

## Autologin

Enrollment turns off Omarchy's automatic sign-in at boot so the login screen appears. `--keep-autologin` keeps it, and
`leave` turns it back on. `monarchy-identity status` shows the current setting.

## Updates

Omarchy updates and migrations can overwrite the sign-in configuration. After any pacman transaction that touches the
relevant packages, monarchy-identity puts its part back automatically. Nothing to set up.

For an extra repair right after `omarchy update`, install Omarchy's post-update hook as the desktop user:

```bash
monarchy-identity install-hooks
monarchy-identity remove-hooks
```

You can also run the repair yourself at any time: `sudo monarchy-identity reassert`. It's safe to run repeatedly, so an
MDM can schedule it if you want to be sure.

## Status widget

The optional `monarchy-identity-shell` package adds a widget to the Omarchy bar that shows whether the laptop is
enrolled, and warns when autologin is on:

```bash
monarchy-identity install-widget --enable    # as the desktop user
monarchy-identity remove-widget
```

The widget only displays status; hiding it changes nothing about who can sign in.
