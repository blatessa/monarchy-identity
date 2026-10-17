# CLI reference

```text
monarchy-identity <command> [options]
```

| Command | Run as | Purpose |
|---|---|---|
| [`status`](#status) | anyone | Show whether the laptop is enrolled and how sign-in is set up |
| [`enroll`](#enroll) | root | Join the directory and set who may sign in |
| [`policy`](#policy) | `show`: anyone, `set`: root | Show or change who may sign in |
| [`leave`](#leave) | root | Leave the directory and remove directory sign-in |
| [`reassert`](#reassert) | root | Put the sign-in configuration back if something overwrote it |
| [`install-hooks`, `remove-hooks`](#install-hooks-remove-hooks) | desktop user | Omarchy post-update hook |
| [`install-widget`, `remove-widget`](#install-widget-remove-widget) | desktop user | Bar widget |
| [`providers`](#providers) | anyone | List the available directory providers |

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
monarchy-identity enroll --realm REALM (--groups A,B | --users U1,U2 | --mode any) [options]
```

Joins the directory and turns on directory sign-in. The join account's password is asked for at a terminal, or read
from `--password-file`, `OI_ADMIN_PASSWORD_FILE` or standard input. `enroll --help` lists every option.

Before it joins, `enroll` checks the password and that the groups you named exist, so typos fail without changing
anything.

**Directory**

| Option | Default | Description |
|---|---|---|
| `--realm R` | required | The directory's domain, such as `corp.example.com`. |
| `--admin USER` | `Administrator` | The join account. |
| `--password-file FILE` | standard input | File holding the join password; must be readable only by its owner. |
| `--server HOST` | found through DNS | Use this domain controller. Leave it off in production. |
| `--computer-name NAME` | hostname | The laptop's name in the directory: up to 15 letters, digits or hyphens. |
| `--ou DN` | directory default | Where the laptop goes, such as `OU=Laptops,DC=corp,DC=example,DC=com`. |
| `--replace-computer-account` | off | Take over an existing computer account with this name (a reinstalled laptop). |

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
| `--if-needed` | off | If already enrolled in this realm, update the policy instead of joining again. See [Automate enrollment](../guides/automation.md). |

## policy

```text
monarchy-identity policy show
monarchy-identity policy set [--groups a,b | --users u1,u2 | --mode any] [--sudo-groups g1,g2 | -] [--offline-days N]
```

`show` prints the realm, who may sign in, `sudo` groups, offline days and the computer name. `set` changes only the
options you pass; `--sudo-groups -` removes `sudo`. See [Change who may sign in](../guides/change-policy.md).

## leave

```text
monarchy-identity leave [--admin USER] [--password-file FILE] [--quiet]
```

Leaves the directory and removes directory sign-in. With `--admin`, also deletes the laptop's computer account. See
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
