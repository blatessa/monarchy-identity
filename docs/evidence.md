# Test evidence

Captures showing that a machine enrolled with monarchy-identity authenticates against a directory. They come from
our test environment: Samba AD `CORP.TEST` in a container and an Arch VM with Omarchy's PAM and SDDM files installed as
fixtures (not a full Omarchy install). The images are command output captured from those machines and rendered to
PNG, not screen recordings. Sign-ins were made over SSH, which uses the same `system-auth` stack as the login screen.
Omarchy's own login screen and lock screen have not been tested; see [Status and limits](status.md).

The policy used is `--groups oi-laptop-users`. `alice` and `bob` are members, `carol` is a directory
user outside the group.

## The directory authenticates users and applies the policy

`alice` signs in with her directory password and holds a Kerberos ticket-granting ticket for `CORP.TEST`. `carol`
exists in the directory and her password is correct (`pam_sss(sshd:auth): authentication success`), but the account
check refuses her because she is not in the permitted group.

![Directory sign-in and policy denial](img/auth-proof.png)

## The login and lock screen PAM services use the same stack

Omarchy's `sddm` and `omarchy-lock-password` services both allow `alice` and deny `carol`. The `pam_sss` rules are
present in `system-auth`, all `-`-prefixed, and `net ads testjoin` reports the join is healthy.

![PAM results for the login and lock screen services](img/auth-pamstack.png)

## The directory side

The laptop's computer object, with its service principal names, and the members of the groups used by that
policy:

![Computer account in the directory](img/dc-computer.png)

![Group membership in the directory](img/dc-groups.png)

## The laptop side

A signed-in directory user: UID and groups resolved from the directory, a home directory created on first sign-in
with mode 0700, and a login session.

![A directory user's session on the laptop](img/vm-signed-in.png)

State kept on the machine: the home directories, `getent` resolution, the configuration and the backups that
`leave` restores, and sssd running.

![Filesystem state on the laptop](img/vm-filesystem.png)
