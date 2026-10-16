# monarchy-identity

Corporate sign-in for [Omarchy](https://omarchy.org), and the identity component of **Monarchy**, a management
suite that aims to make Omarchy a practical work computer.

Enrol a laptop in a company directory (Active Directory / Samba AD today; other providers are pluggable), control
who may sign in, keep that configuration from drifting, and report device posture to whatever management tooling the
company already runs. Directory users sign in at the normal Omarchy login screen, now with a username box.

> **Status: prototype.** Verified end to end in a VM against Samba AD, including the real SDDM login screen (X11
> greeter). **Not yet verified:** Omarchy's own Hyprland-based greeter, the Quickshell lock screen, Windows AD,
> FreeIPA, Entra ID/OIDC. Don't install it on a machine you can't recover. The tool refuses to enrol without a local
> fallback account and can auto-revert (`--confirm-within`) to reduce that risk.

## Documentation

| You are... | Read |
|---|---|
| **Using** a laptop that has it set up | [User guide](docs/user/USER-GUIDE.md), [quick reference](docs/user/QUICK-REFERENCE.md) |
| **Administering** laptops | [Admin guide](docs/ADMIN.md), [posture report schema](docs/POSTURE.md) |
| **Contributing** | [CLAUDE.md](CLAUDE.md) (rules, layout, dev loop), [design](docs/DESIGN.md), [review](docs/REVIEW.md), [TODO](TODO.md), [HANDOFF](HANDOFF.md) |

## What it does

- **Enrol and join.** `monarchy-identity enroll sssd --realm CORP.EXAMPLE.COM --mode groups --groups laptop-users`
  joins the domain, starts sssd, and adds `pam_sss` to the login and lock-screen PAM stacks without disturbing
  local accounts. `--server` is optional (DCs are found through DNS).
- **Login policy.** `groups` (members of listed groups), `assigned` (listed users), or `any` (whole directory,
  explicit opt-in). Default deny. Local break-glass accounts always work.
- **A login screen that works.** Omarchy's stock SDDM theme has no username box (it only logs in the last user), so
  enrolment selects a `monarchy-identity` theme: Omarchy's look plus a username line.
- **Stays correct.** A root-owned systemd path unit repairs the PAM, nsswitch and SDDM edits within seconds if an
  update or a person overwrites them; a pacman hook and an optional `omarchy update` hook do the same.
- **Fleet-safe.** Never takes over an existing computer account, refuses colliding hostnames, supports `--ou` and
  `--computer-name`, and `policy set` changes who may sign in without re-joining. Broken sssd or a missing PAM module
  never locks out local users.
- **Safe to try.** Refuses to enrol without a local fallback account, rolls back (including the directory computer
  account) on any failure, and `--confirm-within N` auto-reverts unless you confirm. `leave` restores the original files.
- **Reports and checks.** `monarchy-identity status --json` is a versioned posture report (identity plus disk
  encryption, firewall, Secure Boot, TPM2, lock timeout); `monarchy-identity check` evaluates it against a policy file and exits 0/1/2.
- **Automation-friendly.** No TTY needed (`--password-file`), strict input validation, an Ansible example in the admin guide.
- **Optional extras.** `--sudo-groups` (directory groups get sudo through a validated drop-in), `--offline-days`
  (cached credentials expire), `--disable-autologin`, password changes and offline login for directory users.

## What it deliberately does not do

Remove admin rights from existing local users, enforce a device-wide privilege model, or harden boot (Secure Boot,
TPM-bound LUKS). Those belong to your MDM or to other Monarchy components; this tool reports on them (`check`) and
leaves enforcement to you. See [docs/DESIGN.md](docs/DESIGN.md).

## Packages

`monarchy-identity` (CLI, providers, hooks, login theme, systemd units; build with `packaging/PKGBUILD`) and the
optional `monarchy-identity-shell` (a Quickshell bar widget showing posture; cosmetic only, not a security boundary).

## Develop and test

`test/run-all.sh` runs every suite (about 10 minutes). It needs Docker (a throwaway Samba AD) and QEMU/KVM (an Arch
client VM); see [test/README.md](test/README.md) and [CLAUDE.md](CLAUDE.md). The unit tests (`test/unit/`) need nothing.

## Contributing and security

[CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) (report vulnerabilities privately)

## License

MIT (see [LICENSE](LICENSE)).
