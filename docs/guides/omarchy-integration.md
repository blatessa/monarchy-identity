# Omarchy integration

How enrollment fits into the parts of Omarchy people see and the parts that update underneath you.

## Login screen

Omarchy's stock login screen signs in whoever used it last and has no username box, so a directory user couldn't type
their name. Enrollment switches the login screen to the `monarchy-identity` theme: Omarchy's own look plus one line for
the username. It follows Omarchy's artwork, so theme changes carry over.

Pass `--keep-login-theme` to opt out; directory users then can't sign in at the login screen (terminals and `ssh`
still work). `status --json` reports `login_theme` and `username_field`.

## Autologin

By default Omarchy signs the first user in automatically at boot on an encrypted disk: the disk passphrase is the
login. If people sign in with their company account, the login screen should appear instead, so enrolling turns
autologin off. Pass `--keep-autologin` to keep it. `monarchy-identity status` shows the effective setting, and the
[compliance policy](compliance-checks.md) can require it off (`forbid_autologin`). `leave` restores the previous setting.

## Lock screen

Omarchy's lock screen has its own sign-in configuration. Enrollment updates it too, so directory users unlock with
their directory password.

## Updates

Omarchy updates and migrations can rewrite sign-in configuration. A watcher repairs it automatically
([Staying correct](../concepts/self-healing.md)). If you also want a repair right after `omarchy update`, install the
optional hook as the desktop user:

```bash
monarchy-identity install-hooks
monarchy-identity remove-hooks
```

It is a convenience; the watcher does not depend on it.

## Status widget

`monarchy-identity-shell` adds an optional widget to the Omarchy bar showing enrollment, login mode and warnings
(autologin on, local admins present):

```bash
monarchy-identity install-widget --enable    # as the desktop user
monarchy-identity remove-widget
```

The widget is a display only: it runs no privileged command and enforces nothing, so hiding it changes nothing about who
can sign in. It has not been loaded in a live Omarchy shell yet.
