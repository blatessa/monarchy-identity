# Omarchy integration

## Login screen

Omarchy's SDDM theme logs in `userModel.lastUser` and has no username field, so a directory user cannot type a name.
Enrollment writes `/etc/sddm.conf.d/zz-monarchy-identity-theme.conf` selecting the `monarchy-identity` theme (the
same look, plus an editable username line). The file name sorts after Omarchy's drop-ins, and SDDM applies the
last value. Skip it with `--keep-login-theme`. `status --json` reports `login_theme` and `username_field`.

The theme's images are symlinks to Omarchy's own, so the look follows Omarchy.

## Autologin

`--disable-autologin` writes `/etc/sddm.conf.d/zz-monarchy-identity.conf` with an empty `[Autologin] User=`. It has
to sort after Omarchy's `autologin.conf`. `status` reports the effective value (all drop-ins merged), and `reassert`
keeps the override; `leave` removes it.

## Lock screen

Omarchy's lock screen authenticates through its own PAM service, `/etc/pam.d/omarchy-lock-password`. Enrollment
edits it like `system-auth`, so directory users unlock with their directory password.

## `omarchy update` hook

```bash
monarchy-identity install-hooks     # as the desktop user, not root
monarchy-identity remove-hooks
```

This installs `10-monarchy-identity-reassert` as an Omarchy `post-update` hook (using `omarchy hook install` when
`omarchy` is on `PATH`, otherwise copying it to `~/.config/omarchy/hooks/post-update.d/`). The hook runs as the user
and calls `sudo -n monarchy-identity reassert`. It is optional; the root-owned path unit
([Self-healing](../concepts/self-healing.md)) does the same without it.

## Status widget

`monarchy-identity-shell` ships a Quickshell bar widget (`monarchy-identity.status`):

```bash
monarchy-identity install-widget --enable    # as the desktop user
monarchy-identity remove-widget
```

It copies the widget to `~/.config/omarchy/plugins/monarchy-identity.status/`, validating it first with
`omarchy plugin validate` when available, and `--enable` runs `omarchy plugin enable ... --section right`. The widget
shows enrollment, login mode and warnings (autologin on, local `wheel` members, or `identity: unavailable` if the
CLI fails). The widget has not been loaded in a live Omarchy shell yet. It is cosmetic: it runs no privileged
command and enforces nothing.
