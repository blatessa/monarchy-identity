# Manage laptops

## Change who may sign in

People: add or remove them in the directory group. Rules: `policy set` on the laptop. It changes only what you pass,
needs no join credentials (Entra ID: the client secret for a group name the laptop hasn't looked up before), and
refuses, changing nothing, a group the directory doesn't have or a policy that lets nobody in.

```bash
monarchy-identity policy show
sudo monarchy-identity policy set --groups laptop-users,contractors
sudo monarchy-identity policy set --users alice,bob
sudo monarchy-identity policy set --sudo-groups laptop-admins     # full sudo for this group
sudo monarchy-identity policy set --sudo-groups -                 # no directory sudo
sudo monarchy-identity policy set --offline-days 14               # Active Directory only
```

![policy show output](../img/policy.png)

Group names for `--sudo-groups`: letters, digits, `.`, `_`, `-`.

## Automate enrollment

The same command for new and enrolled laptops:

```bash
sudo monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser \
  --ou 'OU=Laptops,DC=corp,DC=example,DC=com' --groups laptop-users \
  --password-file /root/join.pw --if-needed
```

- `--password-file` (or `MONARCHY_IDENTITY_PASSWORD_FILE`): the join password (Entra ID: the client secret) on the
  first line, mode 600. Without it, standard input.
- `--if-needed` on a laptop enrolled with the same directory: no re-join, the password isn't used, and the options
  you pass become the whole policy (leaving out `--sudo-groups` removes sudo). Another directory: fails, `leave` first.
- Exit 0 or 1; the reason on standard error and in `journalctl -t monarchy-identity`. State: [`status --json`](../reference/status-output.md).

## Roll out

1. Decide the sign-in group, the sudo group (if any), and `--offline-days` (if any).
2. Prepare the directory: [Active Directory](../providers/ad.md#prepare-the-directory),
   [Entra ID](../providers/entra.md#prepare-the-tenant).
3. Pilot on a few laptops: login screen, text console, lock screen, someone outside the group refused, sign-in with
   the network unplugged after a first sign-in, `leave` and enroll again.
4. Install the package everywhere (it does nothing until enrolled), then enroll with your MDM or a script.

Ongoing: removed people keep cached sign-in on a laptop until it next reaches the directory (`--offline-days` bounds
that). A reinstalled laptop is enrolled again: see [Active Directory](../providers/ad.md#how-it-behaves) for its old
computer account, [Entra ID](../providers/entra.md#how-it-behaves) for its old device. Updates need nothing.

## Leave

```bash
sudo monarchy-identity leave --admin joinuser
```

Removes directory sign-in and everything `enroll` changed (theme, autologin setting, sudo rules). Local accounts and
directory users' home folders stay. Active Directory: with `--admin` the computer account is deleted, without it it
stays. Entra ID: the device stays in Entra; `leave` prints its ID.

## Uninstall

```bash
sudo pacman -R monarchy-identity
```

On an enrolled laptop this runs `leave` first (without directory credentials). Restart before the next sign-in at the
login screen.
