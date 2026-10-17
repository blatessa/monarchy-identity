# Enroll safely

## Dead-man's switch

Pass `--confirm-within MINUTES` on the first enrollment of any machine:

```bash
sudo monarchy-identity enroll sssd --realm CORP.EXAMPLE.COM --admin joinuser \
  --mode groups --groups laptop-users --confirm-within 10
```

`enroll` schedules a transient systemd timer (`monarchy-identity-revert`) that runs `monarchy-identity leave` after
the given number of minutes. To keep the enrollment, sign in as a directory user from another session, then run:

```bash
sudo monarchy-identity confirm
```

`status --json` reports `revert_pending` while the timer is armed. The timer's `leave` has no directory credentials,
so a reverted machine leaves its computer account in the directory; delete it, or re-enroll that name with
`--replace-computer-account`.

## Existing computer accounts

If `NAME$` already exists in the directory and this machine is not joined with it, `enroll` stops. The account may
belong to another laptop, and joining would reset its password. For a genuine re-enrollment of the same laptop, for
example after a reinstall, pass `--replace-computer-account`. Otherwise choose a different name with
`--computer-name`.

## What a failed enrollment does

The machine is restored from `/var/lib/monarchy-identity/backup`, the self-heal unit is not left enabled, and the
computer account created by this run is deleted. The failure message names the cause; the log is in the journal
(`journalctl -t monarchy-identity`).

## Recovery

From a text console (Ctrl+Alt+F3) or SSH as the local fallback account:

```bash
sudo monarchy-identity leave
```

See [Leave and uninstall](leave-and-uninstall.md) and [Troubleshooting](troubleshooting.md).
