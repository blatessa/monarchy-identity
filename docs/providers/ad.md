# Active Directory

The `ad` provider connects laptops to Active Directory or Samba AD. Each laptop joins the domain and gets its own
computer account, and people sign in through `sssd`, the standard Linux directory client.

```bash
sudo monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser --groups laptop-users
```

While `ad` is the only provider installed, `monarchy-identity enroll --realm ...` without the name works too.

## Terms

- **Realm**: the domain's name, such as `CORP.EXAMPLE.COM`. It's what you pass as `--realm`.
- **Join account**: an account allowed to add computers to the domain. Its password is used while enrolling (and,
  optionally, leaving) and never stored.
- **Computer account**: the laptop's own entry in the domain, named after its hostname.
- **OU** (organizational unit): a folder in the domain where laptops' computer accounts can go.

## Prepare the directory

Ask your directory administrator for:

1. **A group** of the people allowed on these laptops (`laptop-users`), and optionally one for `sudo` (`laptop-admins`).
2. **An OU** for the laptops, for example `OU=Laptops,DC=corp,DC=example,DC=com`.
3. **A join account** that can create and delete computer objects in that OU (and reset their passwords, if you'll
   re-enroll reinstalled laptops). Not a Domain Admin.

On Samba AD: `samba-tool group add laptop-users` and `samba-tool group addmembers laptop-users alice`. On Windows AD,
in PowerShell: `New-ADGroup laptop-users -GroupScope Global` and `Add-ADGroupMember laptop-users alice`.

## Prepare the laptops

- **A unique hostname, at most 15 characters.** It becomes the computer account's name. Generic names like `omarchy`
  are refused. Set it with `sudo hostnamectl set-hostname laptop-0042`, or pass `--computer-name`.
- **DNS that finds your domain controllers.** Check with `dig -t SRV _ldap._tcp.corp.example.com`. Laptops on the
  office network or VPN usually get this already; if not, see below.
- **A network path to the domain controllers** while enrolling and for each person's first sign-in: typically DNS (53),
  Kerberos (88, 464), LDAP (389 TCP and UDP) and SMB (445).
- **A correct clock.** Sign-in fails when the clock is more than about five minutes off.

If `dig` lists nothing, the laptop asks a DNS server that doesn't know your domain (typically a test network with a
fixed address, next to Wi-Fi). Send just the domain's lookups to a domain controller, here `10.0.0.10`:

```bash
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nDNS=10.0.0.10\nDomains=~corp.example.com\n' | sudo tee /etc/systemd/resolved.conf.d/corp.conf
sudo systemctl restart systemd-resolved
```

## Enroll options

| Option | Default | Description |
|---|---|---|
| `--realm R` | required | The domain, such as `corp.example.com`. |
| `--admin USER` | `Administrator` | The join account. |
| `--password-file FILE` | standard input | File holding the join password; readable only by its owner. Also `OI_ADMIN_PASSWORD_FILE`. |
| `--server HOST` | found through DNS | Use this domain controller. Leave it off in production. |
| `--computer-name NAME` | hostname | The computer account's name: up to 15 letters, digits or hyphens. |
| `--ou DN` | domain default | Where the computer account goes. |
| `--replace-computer-account` | off | Take over an existing computer account with this name (a reinstalled laptop). |

The options every provider shares (who may sign in, `sudo`, offline days, autologin) are in the
[CLI reference](../reference/cli.md#enroll).

Before it joins, `enroll` checks the join password, that every `--groups` entry exists, and that no other laptop owns
the computer name. If it stops after joining (for example, the network dropped), run the same command again: it
reuses the computer account it created.

## How it behaves

- People sign in with their short name (`alice`), not `alice@corp.example.com` or `CORP\alice`.
- A person has the same user ID on every laptop, derived from the directory.
- `leave --admin joinuser` deletes the computer account. Without the join account, the account stays in the directory;
  delete it there, or the next enrollment with that name needs `--replace-computer-account`.
- A reinstalled laptop keeps its hostname, so its old computer account is in the way: delete it in the directory, or
  enroll with `--replace-computer-account` if you're sure it's the same laptop.

## Troubleshooting

| `enroll` says | What to do |
|---|---|
| `wrong password, or no account named '...'` | Check the join account's name (`--admin`) and its password. |
| `the domain controller name '...' does not resolve` | The laptop's DNS doesn't know the `--server` name. Use the directory's DNS servers, or give `--server` an address. |
| `DNS has no domain controllers for ...` | Without `--server`, domain controllers are found through DNS, and the laptop's DNS doesn't have them. Point it at the directory's DNS servers, or pass `--server`. |
| `no domain controller answered` | The domain controller was found but didn't answer: network, VPN, firewall, or it's down. |
| `the directory has no OU '...'` | Check the `--ou` path; the OU must exist before laptops join into it. |
| `the directory refused the join: ...` | The rest is the directory's own reason. A common one is the join account lacking the right to add computers. |
| `a computer account 'NAME$' already exists` | Another laptop may own that name. Pick another with `--computer-name`, or add `--replace-computer-account` if it's this laptop reinstalled. |
| `the generic '...'` or `longer than 15 characters` | Set a unique, short hostname, or pass `--computer-name`. |
| `already enrolled in '...'` | `--if-needed` with a different realm. Run `leave` first. |
| `accessible by group/other` | `chmod 600` the password file. |

## Status details

`status --json` reports these under `details`: `sssd_active` (the directory client is running), `nss_sss` (the laptop
looks up users in the directory), `pam_system_auth` and `pam_omarchy_lock_password` (sign-in and the lock screen use
the directory), `pam_sddm` (the login screen lets an expired password through to be changed), `domain_joined` (the computer account works; only known as root).

## Known gaps

- Group Policy logon rules are ignored: the [login policy](../concepts/login-policy.md) decides who may sign in.
- Several domain controllers, AD sites and failover are untested.
- Tested against Samba AD only. See [Status and limits](../status.md).
