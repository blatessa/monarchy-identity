# CLI reference

```text
monarchy-identity <command> [options]
```

| Command | Run as | Purpose |
|---|---|---|
| [`status`](#status) | anyone | Show whether the laptop is enrolled and how sign-in is set up |
| [`enroll`](#enroll) | root | Connect to a directory and set who may sign in |
| [`policy`](#policy) | `show`: anyone, `set`: root | Show or change who may sign in |
| [`leave`](#leave) | root | Disconnect from the directory and remove directory sign-in |
| [`reassert`](#reassert) | root | Put the sign-in configuration back if something overwrote it |
| [`install-hooks`, `remove-hooks`](#install-hooks-remove-hooks) | desktop user | Omarchy post-update hook |
| [`providers`](#providers) | anyone | List the installed directory providers |

Every command exits 0 on success and 1 on failure, with the reason on standard error and in the journal
(`journalctl -t monarchy-identity`). `-h` or `--help` prints usage.

## status

```text
monarchy-identity status [--json]
```

Shows whether the laptop is enrolled, the provider, the login mode and autologin. `--json` adds health checks, for
scripts: [Status output](status-output.md).

## enroll

```text
monarchy-identity enroll [PROVIDER] [provider options] (--groups A,B | --users U1,U2 | --mode any) [options]
```

Connects the laptop to a directory and turns on directory sign-in. `PROVIDER` is `ad` (Active Directory), the only
one today; with one installed it can be left out. Its options (`--realm`, `--admin`, `--ou`, ...) are on the
[Active Directory page](../providers/ad.md#enroll-options), with the messages it can refuse with. `enroll --help` lists
every option. Before it changes anything, `enroll` checks what the directory can (credentials, that the groups exist),
so mistakes fail without touching the laptop. A laptop enrolled with one directory must `leave` before enrolling with
another.

**Who may sign in** (see [Who may sign in](../concepts/login-policy.md)). One is required.

| Option | Description |
|---|---|
| `--groups a,b` | Members of these directory groups. |
| `--users u1,u2` | Only these people. |
| `--mode any` | Everyone in the directory. |

**Other options**

| Option | Default | Description |
|---|---|---|
| `--sudo-groups g1,g2` | none | Members of these directory groups get `sudo`. |
| `--offline-days N` | never | Cached sign-in stops working after N days without reaching the directory. |
| `--keep-autologin` | off | Keep Omarchy's automatic sign-in at boot. |
| `--keep-login-theme` | off | Keep Omarchy's stock login screen (it has no username box). |
| `--password-file FILE` | standard input | Where a provider that needs an enrollment password reads it; readable only by its owner. Also `OI_ADMIN_PASSWORD_FILE`. |
| `--if-needed` | off | If already enrolled with this directory, update the policy instead of enrolling again. See [Automate enrollment](../guides/automation.md). |

## policy

```text
monarchy-identity policy show
monarchy-identity policy set [--groups a,b | --users u1,u2 | --mode any] [--sudo-groups g1,g2 | -] [--offline-days N]
```

`show` prints who may sign in, `sudo` groups, offline days and the directory's details. `set` changes only the options
you pass; `--sudo-groups -` removes `sudo`. See [Manage enrolled laptops](../guides/manage.md).

## leave

```text
monarchy-identity leave [provider options] [--quiet]
```

Disconnects the laptop from the directory and removes directory sign-in. Active Directory's `--admin` also deletes the
computer account. See [Manage enrolled laptops](../guides/manage.md#leave-the-directory).

## reassert

```text
monarchy-identity reassert
```

Puts the sign-in configuration back if something overwrote it, and starts the directory service if it stopped. Runs
automatically after package updates; safe any time.

## install-hooks, remove-hooks

```text
monarchy-identity install-hooks
monarchy-identity remove-hooks
```

Adds or removes an Omarchy post-update hook that runs `reassert` after `omarchy update`.

## providers

```text
monarchy-identity providers
```

Lists the directory providers installed.
