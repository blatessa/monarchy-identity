# Active Directory

The `ad` provider joins the laptop to Active Directory or Samba AD as a computer account named after its hostname
(samba `net ads join`, sssd).

```bash
sudo monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser --groups laptop-users
```

`--admin` is an account that may add computers to the domain. Its password is used while enrolling (and leaving, to
delete the computer account) and isn't stored.

## Prepare the directory

1. A group of people allowed to sign in (`laptop-users`), and optionally one for `sudo` (`laptop-admins`).
   Samba: `samba-tool group add laptop-users; samba-tool group addmembers laptop-users alice`.
   Windows: `New-ADGroup laptop-users -GroupScope Global; Add-ADGroupMember laptop-users alice`.
2. An OU for the laptops (`OU=Laptops,DC=corp,DC=example,DC=com`), optional.
3. A join account that can create and delete computer objects there (and reset their passwords, to re-enroll
   reinstalled laptops).

## Prepare the laptops

- Hostname: unique, at most 15 characters, not a generic name like `omarchy` (refused). `sudo hostnamectl
  set-hostname laptop-0042`, or `--computer-name`.
- DNS must find the domain controllers: `dig -t SRV _ldap._tcp.corp.example.com`. If it doesn't, send the domain's
  lookups to a domain controller (`10.0.0.10` here):

  ```bash
  sudo mkdir -p /etc/systemd/resolved.conf.d
  printf '[Resolve]\nDNS=10.0.0.10\nDomains=~corp.example.com\n' | sudo tee /etc/systemd/resolved.conf.d/corp.conf
  sudo systemctl restart systemd-resolved
  ```

- Reachable domain controllers while enrolling and at each person's first sign-in: DNS 53, Kerberos 88 and 464,
  LDAP 389 (TCP and UDP), SMB 445.
- Clock within 5 minutes: `timedatectl` shows "System clock synchronized: yes".

## Enroll options

| Option | Default | |
|---|---|---|
| `--realm R` | required | The domain |
| `--admin USER` | required | The join account |
| `--password-file FILE` | standard input | Join password, mode 600. Also `MONARCHY_IDENTITY_PASSWORD_FILE`. |
| `--server HOST` | DNS | A specific domain controller |
| `--computer-name NAME` | hostname | Up to 15 letters, digits, hyphens |
| `--ou DN` | domain default | Where the computer account goes |
| `--replace-computer-account` | off | Take over an existing computer account of this name (a reinstalled laptop) |

Shared options: [CLI reference](../reference/cli.md#enroll). Before joining, `enroll` checks the join password, every
`--groups` entry, and that no other machine owns the computer name. If it stops partway, run it again.

## How it behaves

- Sign-in names are short (`alice`, not `alice@corp.example.com` or `CORP\alice`). UIDs are the same on every laptop.
- `leave --admin joinuser` deletes the computer account; plain `leave` leaves it in the directory.
- A reinstalled laptop finds its old computer account in the way: delete it, or enroll with
  `--replace-computer-account`.

## Troubleshooting

| `enroll` says | Fix |
|---|---|
| `wrong password, or no account named '...'` | Check `--admin` and its password. |
| `does not resolve`, `DNS has no domain controllers` | Fix DNS ([above](#prepare-the-laptops)) or pass `--server` an address. |
| `no domain controller answered` | Network, VPN, firewall, or the DC is down. |
| `the directory has no OU '...'` | Create the OU or fix `--ou`. |
| `the directory refused the join: ...` | The directory's reason follows; usually the join account lacks rights. |
| `a computer account 'NAME$' already exists` | Another `--computer-name`, or `--replace-computer-account` for this laptop reinstalled. |
| `the generic '...'`, `longer than 15 characters` | Set a unique short hostname or pass `--computer-name`. |
| `already enrolled in '...'` | `leave` first. |

## Status details

`status --json` `details`, each `"true"` when healthy:

| Key | |
|---|---|
| `sssd_active` | sssd is running |
| `nss_sss` | `sss` is in nsswitch |
| `pam_system_auth`, `pam_omarchy_lock_password` | Sign-in and the lock screen use the directory |
| `pam_sddm` | The login screen sends an expired password to the change screen |
| `domain_joined` | The computer account works (`"unknown"` unless run as root) |
