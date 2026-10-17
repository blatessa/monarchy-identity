# Plan a rollout

Settle these before enrolling more than a test machine.

## Directory

**Join account.** Use a dedicated account rather than a Domain Admin. It needs the right to create and delete
computer objects in the OU where laptops will live (delegate this on the OU). `enroll` uses it for `net ads join`
and, on rollback or `leave --admin`, to delete the computer account. The account's password is never stored.

**Organisational unit.** Create an OU for laptops and pass `--ou 'OU=Laptops,DC=corp,DC=example,DC=com'` so computer
accounts land where your delegation and policy expect them. The DN is validated and converted to the form samba's
`createcomputer=` takes; nested OUs work (`OU=Corp,OU=Laptops,...`). Without `--ou`, the account is created in the
default computers container.

**Groups.** Create a security group of users who may sign in (for example `laptop-users`), and optionally a group for
sudo (for example `laptop-admins`, used with `--sudo-groups`). An empty or missing group admits nobody, and `enroll`
refuses to touch PAM if the first listed group does not resolve.

## Laptops

**Unique hostnames.** The hostname becomes the NetBIOS computer account name, upper-cased. It must be 1-15 letters,
digits or hyphens, not start or end with a hyphen, and not be one of `localhost`, `localhost-localdomain`,
`archlinux`, `omarchy`, `arch`. Two machines that share a name would fight over one account. Set it with
`hostnamectl set-hostname NAME`, or override per machine with `--computer-name NAME`.

**DNS.** Omit `--server` in production so domain controllers are discovered through SRV records. The DNS server the
laptop uses must resolve the domain. With `--server`, krb5 and sssd are pinned to that host; without it they use DNS
discovery. Site-aware DC selection is not implemented.

**Clock.** Run NTP. Kerberos fails beyond about five minutes of skew. `status --json` reports `time_sync`, and
[`require_time_sync`](../reference/policy-file.md) can enforce it.

**Local fallback account.** Every laptop needs a local user with a password for break-glass use. Enrolment refuses
without one.

## Omarchy decisions

**Autologin.** Omarchy enables SDDM autologin on encrypted disks, where the disk passphrase is the login. With
directory sign-in you normally want `--disable-autologin`; the alternative is to accept autologin and rely on the
lock screen. The forbid_autologin rule in a [compliance policy](../reference/policy-file.md) can enforce the choice.
See [Omarchy integration](omarchy-integration.md).

**Login theme.** Enrolment switches SDDM to the `monarchy-identity` theme because Omarchy's stock theme has no
username box. `--keep-login-theme` opts out, and directory users then cannot sign in at the login screen.

**Sudo.** `--sudo-groups` is optional and maps whole directory groups to full sudo. If your MDM owns privilege,
leave it off.

## Distribution

Build `packaging/PKGBUILD` with `makepkg`, or use the package from a
[release](https://github.com/blatessa/monarchy-identity/releases), and publish it to a pacman repository you control
(`repo-add`, signed) so the fleet installs and updates it with `pacman`. Installing does nothing until enrolment.

## Order of work

1. Enrol a virtual machine against a test OU. Run `leave` and enrol again.
2. Pilot on a few machines with `--confirm-within`.
3. Script the rollout ([Automate enrolment](automation.md)) and add a [compliance check](compliance-checks.md).
