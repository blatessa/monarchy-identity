# CLI reference

```text
monarchy-identity <command> [options]
```

Commands marked *root* must run as root. Commands marked *user* must not run as root. State-changing commands
(`enroll`, `leave`, `reassert`, `confirm`, `policy`) serialise on `/run/monarchy-identity.lock` when run as root.

| Command | Privilege | Purpose |
|---|---|---|
| [`status`](#status) | any | Show enrollment and posture |
| [`enroll`](#enroll) | root | Enroll with a provider |
| [`leave`](#leave) | root | Unenroll and restore the previous configuration |
| [`policy`](#policy) | `show`: any, `set`: root | Show or change who may sign in |
| [`check`](#check) | any | Evaluate posture against the policy file |
| [`confirm`](#confirm) | root | Cancel a pending auto-revert |
| [`reassert`](#reassert) | root | Re-apply managed `/etc` edits |
| [`install-hooks`, `remove-hooks`](#install-hooks-remove-hooks) | user | Omarchy post-update hook |
| [`install-widget`, `remove-widget`](#install-widget-remove-widget) | user | Bar widget |
| [`providers`](#providers) | any | List providers |

`-h`, `--help` or no command prints usage and exits 0. An unknown command prints usage and exits 1.

## status

```text
monarchy-identity status [--json]
```

Read-only. Without `--json` it prints `enrolled`, `provider`, `login mode`, `autologin`, `wheel members`,
`disk encrypted`, `firewall`, `secure boot`, `tpm2` and `time sync`. With `--json` it prints the
[posture report](posture.md). Some values (`domain_joined`) need root to be determined.

## enroll

```text
monarchy-identity enroll <provider> [options]
```

Runs `providers/<provider>/enroll`. Options for the `sssd` provider (the only directory provider) follow. The join
account's password is read from `--password-file`, `OI_ADMIN_PASSWORD_FILE`, or the first line of stdin.

**Directory**

| Option | Default | Description |
|---|---|---|
| `--realm R` | required | AD or Samba AD realm, a DNS name containing a dot (`corp.example.com`). |
| `--server HOST` | DNS discovery | Pin a domain controller. When omitted, krb5, samba and sssd discover DCs through SRV records. |
| `--admin USER` | `Administrator` | Account used to join. Letters, digits and `. _ @ \ -`, up to 128 characters. |
| `--password-file FILE` | stdin | File holding the password. Must be a regular file owned by root or the caller, with no group or other permissions. |
| `--computer-name NAME` | hostname | Computer account name: 1-15 letters, digits or hyphens, not starting or ending with a hyphen. Upper-cased. |
| `--ou DN` | directory default | Create the account in this OU, e.g. `OU=Laptops,DC=corp,DC=example,DC=com`. Must be `OU=`/`CN=` parts followed by `DC=` parts. |
| `--replace-computer-account` | off | Allow joining with a name that already exists in the directory. |

**Login policy** (see [Login policy](../concepts/login-policy.md))

| Option | Default | Description |
|---|---|---|
| `--mode groups\|assigned\|any` | `groups` | Who may sign in. |
| `--groups a,b` | | Required for `groups`. |
| `--users u1,u2` | | Required for `assigned`. |

**Optional features**

| Option | Default | Description |
|---|---|---|
| `--sudo-groups g1,g2` | none | Give these directory groups full sudo through `/etc/sudoers.d/50-monarchy-identity`. Letters, digits, `. _ -`. |
| `--offline-days N` | `0` (never) | Cached credentials expire after N days without reaching a DC. |
| `--disable-autologin` | off | Override SDDM autologin. |
| `--keep-login-theme` | off | Do not switch SDDM to the `monarchy-identity` theme. |

**Safety and automation**

| Option | Default | Description |
|---|---|---|
| `--confirm-within MINUTES` | `0` (off) | Run `leave` after this many minutes unless `confirm` is run. |
| `--allow-no-local-fallback` | off | Skip the check that a local account with a usable password exists. |
| `--if-needed` | off | If already enrolled in the same realm, converge the policy without re-joining. Fails for a different realm. See [Automate enrollment](../guides/automation.md). |

Unknown options are an error. Exit status is 0 on success, 1 on failure. A failure after the machine was modified
triggers a rollback.

## leave

```text
monarchy-identity leave [--admin USER] [--password-file FILE] [--quiet]
```

Runs the provider's `unenroll`. With `--admin`, deletes the computer account using the supplied credentials;
otherwise tries machine credentials and warns if the account remains. `--quiet` suppresses the summary. On a machine
that is not enrolled (provider `local`) it does nothing.

## policy

```text
monarchy-identity policy show
monarchy-identity policy set [--mode M] [--groups a,b] [--users u1,u2] [--sudo-groups g1,g2|-] [--offline-days N]
```

`show` prints realm, login mode, groups, users, sudo groups, offline days and the computer name. `set` changes only
the options given; `--sudo-groups -` removes sudo access. See [Change who may sign in](../guides/change-policy.md).
Fails if the machine is not enrolled with the sssd provider.

## check

```text
monarchy-identity check [--json]
```

Evaluates `status --json` against `/etc/monarchy-identity/policy.toml` (override with `MONARCHY_IDENTITY_POLICY`).
Exit 0 compliant, 1 violations, 2 bad policy or input. See [Compliance policy file](policy-file.md).

## confirm

```text
monarchy-identity confirm
```

Cancels the pending auto-revert timer. Prints `no auto-revert pending` if there is none.

## reassert

```text
monarchy-identity reassert
```

Re-applies the managed nsswitch, PAM, autologin, sudoers and theme edits from the saved configuration and starts
sssd if it is stopped. Called by the path unit, the pacman hook and the Omarchy hook. See
[Self-healing](../concepts/self-healing.md).

## install-hooks, remove-hooks

```text
monarchy-identity install-hooks
monarchy-identity remove-hooks
```

Install or remove the Omarchy `post-update` hook `10-monarchy-identity-reassert` for the current user. Refuse to
run as root.

## install-widget, remove-widget

```text
monarchy-identity install-widget [--enable]
monarchy-identity remove-widget
```

Install the Quickshell bar widget into `~/.config/omarchy/plugins/monarchy-identity.status/` (needs the
`monarchy-identity-shell` package), or remove it. `--enable` also runs `omarchy plugin enable`. Refuse to run as root.

## providers

```text
monarchy-identity providers
```

Lists the directories under `providers/`.
