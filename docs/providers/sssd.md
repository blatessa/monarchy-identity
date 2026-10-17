# sssd provider (Active Directory)

Joins an Active Directory or Samba AD domain and authenticates through sssd.

## Requirements

`sssd`, `samba` (for `net`), `krb5` and `python3`, all in the Arch repositories. `adcli` and `oddjob` are not used
because they are AUR-only. Home directories are created by `pam_mkhomedir` (mode 0700).

## Join

The join uses `net ads join` (twice: on a brand-new computer account the first join produces a machine key that
sssd's `ldap_child` rejects until the password is reset by a second join). The keytab is then rebuilt with
`net ads keytab create` using the admin credentials and verified with `kinit -k`. DNS updates are disabled
(`--no-dns-updates`).

With `--server`, samba commands use `-S HOST` and krb5 is pinned to that host. Without it, krb5
(`dns_lookup_kdc`), samba and sssd use SRV discovery.

## Generated configuration

`/etc/sssd/sssd.conf`:

```ini
[sssd]
services = nss, pam
domains = corp.example.com

[domain/corp.example.com]
id_provider = ad
auth_provider = ad
chpass_provider = ad
# groups mode:   access_provider = simple  +  simple_allow_groups = <groups>
# assigned mode: access_provider = simple  +  simple_allow_users = <users>
# any mode:      access_provider = permit
ad_domain = corp.example.com
krb5_realm = CORP.EXAMPLE.COM
ad_server = <server>                 # only with --server
ad_hostname = <hostname>.corp.example.com
ldap_sasl_authid = <COMPUTER>$
ad_gpo_access_control = disabled
dyndns_update = false
use_fully_qualified_names = False
fallback_homedir = /home/%u
default_shell = /bin/bash
ldap_id_mapping = True
cache_credentials = True
krb5_store_password_if_offline = True

# only with --offline-days N:
[pam]
offline_credentials_expiration = N
```

`/etc/samba/smb.conf` sets `security = ads`, the realm, the workgroup (first label of the realm), the NetBIOS name
and `kerberos method = secrets and keytab`. `/etc/krb5.conf` sets the default realm and the domain-to-realm
mapping.

User IDs come from `ldap_id_mapping = True`, so they are derived from the directory SID and are identical on every
machine in the domain.

## Status keys

`providers/sssd/status` prints `sssd_active`, `nss_sss`, `pam_system_auth`, `pam_omarchy_lock_password` and
`domain_joined`; they appear under `details` in the [posture report](../reference/posture.md).

## Known gaps

- GPO access control is disabled; GPO logon rights are ignored.
- Dynamic DNS updates are off; AD site selection and DC failover are untested.
- Tested only against Samba AD. See [Status and limits](../status.md).
