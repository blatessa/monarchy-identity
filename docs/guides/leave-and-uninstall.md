# Leave and uninstall

## Leave the directory

```bash
sudo monarchy-identity leave --admin joinuser --password-file /root/join.pw
```

`leave` runs, in order: disable the self-heal path unit, remove the SDDM autologin override and theme drop-in,
remove the sudoers drop-in, remove the PAM edits, remove `sss` from nsswitch, stop and disable sssd, leave the
domain, restore the backed-up `krb5.conf`, `smb.conf`, `sssd.conf` and `krb5.keytab`, clear the sssd cache, and
record `provider = "local"`.

With `--admin USER` (password from stdin or `--password-file`), the computer account is deleted from the directory.
Without it, `leave` tries the machine's own credentials and, if that fails, logs a warning and leaves the account.
A directory admin must then delete it, or the next enrolment of that name needs `--replace-computer-account`.

`leave --quiet` suppresses the summary line.

## Uninstall

Removing the package while enrolled runs `monarchy-identity leave` first (without credentials), so PAM edits never
outlive the tool:

```bash
sudo pacman -R monarchy-identity
```

Package upgrades do not run `leave`.
