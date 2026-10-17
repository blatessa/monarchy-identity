# Security policy

monarchy-identity edits PAM, nsswitch, SDDM and sudoers configuration and handles directory credentials, so
security reports are taken seriously.

**Please report vulnerabilities privately** using GitHub's "Report a vulnerability" (Security advisories) on this
repository, not a public issue. Include the version/commit, what you did, what you expected, and the impact.

Particularly interested in: ways to bypass the login policy (`groups` / `assigned`), ways to lock out local users or
root, credential exposure (enrollment credentials are only ever read from stdin or a 0600 file), unsafe handling of
admin-supplied values (these are validated before reaching any configuration file, such as the AD provider's `sssd.conf`, `smb.conf`, `krb5.conf`, or sudoers),
and anything that lets an unprivileged user alter the managed configuration.

Known limits are listed in [the documentation](docs/status.md); this is a prototype; only the Active Directory
provider exists, verified against Samba AD in a VM. Do not rely on it for production without your own testing.
