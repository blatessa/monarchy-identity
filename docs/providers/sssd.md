# Active Directory (sssd)

The default provider. It joins the laptop to an Active Directory or Samba AD domain and signs people in through
`sssd`, the standard Linux directory client.

## What it needs

- The `sssd`, `samba` and `krb5` packages from the Arch repositories (installed as dependencies).
- A join account, a group for the people allowed to sign in, and DNS that finds your domain controllers: see
  [Roll out to a fleet](../guides/rollout.md#2-prepare-the-directory).

## How it behaves

- People sign in with their short name (`alice`), not `alice@corp.example.com` or `CORP\alice`.
- A person has the same user ID on every laptop, derived from the directory, so shared disks and backups line up.
- Home folders are created on first sign-in, private to their owner.
- Laptops find domain controllers through DNS unless you pin one with `--server`.
- The laptop doesn't register itself in DNS.

## Known gaps

- Group Policy logon rules are ignored: the [login policy](../concepts/login-policy.md) decides who may sign in.
- Several domain controllers, AD sites and failover are untested.
- Tested against Samba AD only. See [Status and limits](../status.md).
