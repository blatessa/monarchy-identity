# CLI reference

```text
monarchy-identity <command> [options]
```

| Command | Run as | |
|---|---|---|
| [`status`](#status) | anyone | Enrollment and health |
| [`enroll`](#enroll) | root | Connect to a directory, set who may sign in |
| [`policy`](#policy) | `show`: anyone, `set`: root | Show or change who may sign in |
| [`leave`](#leave) | root | Disconnect and remove directory sign-in |
| [`reassert`](#reassert) | root | Re-apply the sign-in configuration |
| [`install-hooks`, `remove-hooks`](#install-hooks-remove-hooks) | desktop user | Omarchy post-update hook |
| [`providers`](#providers) | anyone | Installed providers |

Exit 0 on success, 1 on failure; the reason goes to standard error and `journalctl -t monarchy-identity`. `--help` on
any command prints its usage.

## status

```text
monarchy-identity status [--json]
```

`--json`: [Status output](status-output.md).

## enroll

```text
monarchy-identity enroll [PROVIDER] [provider options] (--groups A,B | --users U1,U2 | --mode any) [options]
```

`PROVIDER` is `ad` or `entra`; optional when only one is installed. Provider options:
[Active Directory](../providers/ad.md#enroll-options), [Entra ID](../providers/entra.md#enroll-options).
Everything the directory can reject is checked before anything changes. Enrolling again with the same directory keeps
the laptop's registration; another directory needs `leave` first.

| Option | Default | |
|---|---|---|
| `--groups a,b` | | Members of these directory groups may sign in |
| `--users u1,u2` | | These people may sign in |
| `--mode any` | | Everyone in the directory may sign in |
| `--sudo-groups g1,g2` | none | Full `sudo` for these groups |
| `--offline-days N` | no expiry | Cached sign-in stops after N days without the directory. Refused by Entra ID. |
| `--keep-autologin` | off | Keep Omarchy's autologin |
| `--password-file FILE` | standard input | Enrollment secret, mode 600. Also `MONARCHY_IDENTITY_PASSWORD_FILE`. |
| `--if-needed` | off | Already enrolled with this directory: apply the policy instead ([details](../guides/manage.md#automate-enrollment)) |

## policy

```text
monarchy-identity policy show
monarchy-identity policy set [--groups a,b | --users u1,u2 | --mode any] [--sudo-groups g1,g2 | -] [--offline-days N] [--password-file FILE]
```

`set` changes only what's passed; `--sudo-groups -` removes sudo. Entra ID reads the client secret (file or standard
input) only for a group name it hasn't looked up before.

## leave

```text
monarchy-identity leave [provider options] [--quiet]
```

Active Directory: `--admin USER` also deletes the computer account. Entra ID: prints the device ID to delete in Entra.

## reassert

```text
monarchy-identity reassert
```

Re-applies PAM, nsswitch, SDDM and sudoers, and starts the directory client if stopped. The pacman hook runs it after
package updates.

## install-hooks, remove-hooks

Add or remove an Omarchy post-update hook (`~/.config/omarchy/hooks`) that runs `reassert` after `omarchy update`.

## providers

Lists the installed providers.
