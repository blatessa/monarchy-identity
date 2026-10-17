# Leave and uninstall

## Leave the directory

```bash
sudo monarchy-identity leave
```

`leave` turns off directory sign-in, disconnects the laptop from the directory and removes the changes enrollment made:
the login theme, the autologin setting and any `sudo` rule. Local accounts are untouched. Home folders of directory
users stay on disk.

If enrolling created something in the directory, the provider removes it when it can. Active Directory, for example,
deletes the laptop's computer account when you add `--admin joinuser`
([details](../providers/ad.md#how-it-behaves)).

## Uninstall

```bash
sudo pacman -R monarchy-identity
```

Removing the package from an enrolled laptop runs `leave` first (without directory credentials). Package upgrades don't.
