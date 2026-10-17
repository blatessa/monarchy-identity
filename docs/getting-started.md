# Getting started

Enrol one Omarchy machine in an Active Directory domain and confirm that a directory user can sign in. Do this on a
virtual machine or a spare laptop first: it edits PAM.

## Prerequisites

| Requirement | Why |
|---|---|
| Omarchy (Arch Linux), root access | The package edits `/etc` and manages systemd units. |
| A reachable domain controller | By default DCs are found through DNS SRV records. Pass `--server HOST` if DNS discovery is not available. |
| An account that may join computers | Its password is read from stdin or a file. |
| A directory group for permitted users | The default policy is deny; `--mode groups` needs `--groups`. |
| A unique hostname of at most 15 characters | The hostname becomes the computer account. Generic names (`localhost`, `archlinux`, `omarchy`, `arch`) and longer names are refused; use `--computer-name` to override. |
| A local account with a password | Enrolment refuses without one, so a directory failure cannot lock you out. |
| A correct clock | Kerberos fails when the clock is off by more than about five minutes. |

## Install

From a release: download the `.pkg.tar.zst` files and `SHA256SUMS` from the
[releases page](https://github.com/blatessa/monarchy-identity/releases), then:

```bash
sha256sum -c --ignore-missing SHA256SUMS
sudo pacman -U monarchy-identity-*.pkg.tar.zst
```

From source:

```bash
git clone https://github.com/blatessa/monarchy-identity
cd monarchy-identity/packaging && makepkg -si
```

The package depends on `bash`, `python`, `sssd`, `samba` and `krb5`. Installing changes nothing until you enrol.
`monarchy-identity-shell` is an optional status widget for the Omarchy bar.

## Enrol

```bash
sudo monarchy-identity enroll sssd \
  --realm CORP.EXAMPLE.COM --admin joinuser \
  --mode groups --groups laptop-users \
  --disable-autologin --confirm-within 10
```

The command reads `joinuser`'s password from stdin. `--confirm-within 10` schedules an automatic `leave` in ten
minutes unless you confirm, so a bad enrolment undoes itself. On any failure `enroll` rolls the machine back and
deletes the computer account it created. See [Enrol safely](guides/enrol-safely.md).

## Verify

```bash
monarchy-identity status
```

![status output after enrolment](img/status.png)

`enrolled: true` and the expected `login mode` mean the configuration is in place. Then check an actual sign-in as a
directory user from a second session (a text console with Ctrl+Alt+F3, or SSH), not the session you enrolled from:

```bash
getent passwd alice          # resolves through sssd
ssh alice@this-laptop        # directory password
```

A user outside the permitted group must be refused. [Evidence from the lab](evidence.md) shows both outcomes.

## Confirm

When a directory user can sign in, cancel the pending revert:

```bash
sudo monarchy-identity confirm
```

## Next

- [Plan a rollout](guides/rollout-planning.md) before touching more than one machine.
- [Change who may sign in](guides/change-policy.md) without re-joining.
- [Compliance checks](guides/compliance-checks.md) to evaluate posture.
- To undo everything: [Leave and uninstall](guides/leave-and-uninstall.md).
