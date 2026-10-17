# Leave and uninstall

## Leave the directory

```bash
sudo monarchy-identity leave --admin joinuser --password-file /root/join.pw
```

`leave` returns the laptop to exactly how it was before enrolling: the sign-in configuration, login theme, autologin
setting and any `sudo` rule are restored from the backups taken at enrollment, the sign-in service is stopped, the
laptop leaves the domain, and the watcher is switched off first so it can't undo the removal. Local accounts are
untouched throughout. The step-by-step is in [What enroll does](../reference/enrollment-steps.md).

With `--admin USER` (password from stdin or `--password-file`), the computer account is deleted from the directory.
Without it, `leave` tries the machine's own credentials and, if that fails, logs a warning and leaves the account.
A directory admin must then delete it, or the next enrollment of that name needs `--replace-computer-account`.

`leave --quiet` suppresses the summary line.

## Uninstall

Removing the package while enrolled runs `monarchy-identity leave` first (without credentials), so PAM edits never
outlive the tool:

```bash
sudo pacman -R monarchy-identity
```

Package upgrades do not run `leave`.
