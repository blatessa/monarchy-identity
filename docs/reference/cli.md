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
| [`install-widget`, `remove-widget`](#install-widget-remove-widget) | desktop user | Bar widget |
| [`providers`](#providers) | anyone | List the installed directory providers |

Every command exits 0 on success and 1 on failure, with the reason on standard error and in the journal
(`journalctl -t monarchy-identity`). `-h` or `--help` prints usage.

## status

```text
monarchy-identity status [--json]
```

Shows whether the laptop is enrolled, the provider, the login mode and whether autologin is on. `--json` prints the
same and more for scripts: see [Status output](status-output.md).

## enroll

```text
monarchy-identity enroll [PROVIDER] [provider options] (--groups A,B | --users U1,U2 | --mode any) [options]
```

Connects the laptop to a directory and turns on directory sign-in. `PROVIDER` names the directory's
[provider](../providers/index.md); when only one is installed (today, `ad`), it can be left out. `enroll --help` lists
every option, and `enroll PROVIDER --help` adds that provider's. A laptop enrolled with one directory must `leave`
before enrolling with another.

Before it changes anything, `enroll` checks what the directory can check (credentials, that the groups you named
exist), so typos fail without touching the laptop.

**Provider options** are on each provider's page, for example [Active Directory](../providers/ad.md#enroll-options)
(`--realm`, `--admin`, `--ou`, ...).

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

`show` prints the directory, who may sign in, `sudo` groups and offline days, plus provider details (for Active
Directory, the computer name). `set` changes only the options you pass; `--sudo-groups -` removes `sudo`. See
[Change who may sign in](../guides/change-policy.md).

## leave

```text
monarchy-identity leave [provider options] [--quiet]
```

Disconnects the laptop from the directory and removes directory sign-in. Provider options (such as Active Directory's
`--admin`, to delete the computer account) are on the provider's page. See
[Leave and uninstall](../guides/leave-and-uninstall.md).

## reassert

```text
monarchy-identity reassert
```

Puts the sign-in configuration back if an update or a person overwrote it, and starts the directory service if it has
stopped. Runs automatically after package updates; safe to run any time.

## install-hooks, remove-hooks

```text
monarchy-identity install-hooks
monarchy-identity remove-hooks
```

Adds or removes an Omarchy post-update hook that runs `reassert` after `omarchy update`. Run as the desktop user.

## install-widget, remove-widget

```text
monarchy-identity install-widget [--enable]
monarchy-identity remove-widget
```

Adds or removes the Omarchy bar widget (needs the `monarchy-identity-shell` package). `--enable` also shows it in the
bar. Run as the desktop user.

## providers

```text
monarchy-identity providers
```

Lists the directory providers installed. See [Providers](../providers/index.md).
