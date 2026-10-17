# Leave and uninstall

## Leave the directory

```bash
sudo monarchy-identity leave --admin joinuser
```

`leave` turns off directory sign-in, takes the laptop out of the domain and removes the changes enrollment made: the
login theme, the autologin setting and any `sudo` rule. Local accounts are untouched. Home folders of directory users
stay on disk.

With `--admin` (password prompted, from standard input, or `--password-file`), the laptop's computer account is deleted
from the directory. Without it, `leave` tries the laptop's own credentials; if that fails it warns and the account stays.
Delete it in the directory, or the next enrollment with that name needs `--replace-computer-account`.

## Uninstall

```bash
sudo pacman -R monarchy-identity
```

Removing the package from an enrolled laptop runs `leave` first (without directory credentials). Package upgrades don't.
