# Security policy

monarchy-identity changes how a laptop signs people in and handles directory credentials, so security reports are
taken seriously.

**Report vulnerabilities privately** with GitHub's [Report a vulnerability](https://github.com/blatessa/monarchy-identity/security/advisories/new),
not a public issue. Include the version, what you did, what you expected, and the impact.

Especially interesting:

- bypassing the login policy (who may sign in);
- locking out local users or root;
- exposing enrollment credentials (they're only read from standard input or a file readable only by its owner);
- getting an unvalidated value into the configuration it writes;
- an unprivileged user changing the managed configuration.

Security fixes go into the latest release.
