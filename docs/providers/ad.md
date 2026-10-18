# Active Directory

The `ad` provider connects laptops to Active Directory or Samba AD. Each laptop joins the domain with its own
**computer account**, named after its hostname.

```bash
sudo monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser --groups laptop-users
```

`--realm` is the domain's name. `--admin` is the **join account**, an account allowed to add computers to the domain;
its password is used while enrolling (and, optionally, leaving) and never stored. While `ad` is the only provider
installed, the `ad` can be left out.

## Prepare the directory

Ask your directory administrator for:

1. **A group** of the people allowed on these laptops (`laptop-users`), and optionally one for `sudo` (`laptop-admins`).
2. **An OU** (a folder in the domain) for the laptops, for example `OU=Laptops,DC=corp,DC=example,DC=com`.
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
- **A correct clock.** Sign-in fails when the clock is more than about five minutes off. `timedatectl` should say
  "System clock synchronized: yes".

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
the computer name. If it stops partway (the network dropped), run the same command again.

## How it behaves

- People sign in with their short name (`alice`), not `alice@corp.example.com` or `CORP\alice`, and have the same user
  ID on every laptop.
- `leave --admin joinuser` deletes the computer account; without it the account stays in the directory.
- A reinstalled laptop's old computer account is in the way: delete it in the directory, or enroll with
  `--replace-computer-account` if you're sure it's the same laptop.

## Troubleshooting

| `enroll` says | What to do |
|---|---|
| `wrong password, or no account named '...'` | Check `--admin` and its password. |
| `does not resolve`, or `DNS has no domain controllers` | The laptop's DNS doesn't know the domain: see [Prepare the laptops](#prepare-the-laptops), or give `--server` an address. |
| `no domain controller answered` | Found, but no answer: network, VPN, firewall, or it's down. |
| `the directory has no OU '...'` | Check `--ou`; the OU must exist first. |
| `the directory refused the join: ...` | The directory's own reason follows; often the join account lacks the right to add computers. |
| `a computer account 'NAME$' already exists` | Pick another `--computer-name`, or `--replace-computer-account` if it's this laptop reinstalled. |
| `the generic '...'` or `longer than 15 characters` | Set a unique, short hostname, or pass `--computer-name`. |
| `already enrolled in '...'` | Enrolled with another domain: `leave` first. |

## Status details

`status --json` reports these under `details`, each `"true"` when healthy:

| Key | Means |
|---|---|
| `sssd_active` | The directory client is running. |
| `nss_sss` | The laptop looks people up in the directory. |
| `pam_system_auth`, `pam_omarchy_lock_password` | Sign-in and the lock screen use the directory. |
| `pam_sddm` | The login screen sends an expired password to the change-password screen. |
| `domain_joined` | The computer account works (`"unknown"` unless run as root). |
