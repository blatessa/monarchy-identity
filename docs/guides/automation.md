# Automate enrollment

Run one command on every laptop, every time: on a new laptop it enrolls, on an enrolled one it brings the policy up to
date. Put the join account's password in a root-only file for the length of the run, then delete it.

```bash
sudo monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser \
  --ou 'OU=Laptops,DC=corp,DC=example,DC=com' \
  --groups laptop-users \
  --password-file /root/join.pw --if-needed
```

- **The password file** (`--password-file`, or `MONARCHY_IDENTITY_PASSWORD_FILE`) holds the password on its first line and must
  be readable only by its owner (`chmod 600`). Without it, the password is read from standard input. Never pass a
  password as an argument.
- **On an enrolled laptop** nothing is re-registered and the password isn't used. The options you pass become the whole
  policy: leaving out `--sudo-groups` removes `sudo`, leaving out `--offline-days` removes the expiry. (With
  [`policy set`](manage.md), only what you pass changes.) A laptop enrolled with another domain fails: `leave` first.
- **Results:** exit status 0 or 1, with the reason on standard error and in `journalctl -t monarchy-identity`.
  Enrolled laptops log `converging policy without re-joining`. For a laptop's state, use
  [`status --json`](../reference/status-output.md).
