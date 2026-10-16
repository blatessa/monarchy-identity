# omarchy-identity

Corporate sign-in for [Omarchy](https://omarchy.org): enrol a laptop in a directory (Active Directory today; other providers pluggable), control who may log in, and report posture to whatever management tooling the company already runs.

**Status:** prototype. Verified end to end in a VM (enrol with or without `--server`, login policy, offline login, drift repair via pacman hook, autologin override, lockout safety, leave). Not yet tested on a real Omarchy desktop session. Do not install on a machine you can't recover.

## What it does
- `omarchy-identity enroll sssd --realm CORP.EXAMPLE --server dc.corp.example --mode groups --groups laptop-users`
  joins the domain, starts sssd, and adds `pam_sss` to the login and lock-screen PAM stacks without disturbing local accounts.
- **Login policy** (`--mode`): `groups` (members of listed groups), `assigned` (listed users), `any` (whole directory, explicit opt-in). Default deny. Local break-glass accounts always work.
- `omarchy-identity status --json` reports enrolment, provider, policy, autologin, wheel members and PAM/NSS drift, for an MDM, osquery or Ansible to read.
- `omarchy-identity reassert` re-applies the edits after `omarchy update` or a `pambase` upgrade overwrites them (also wired as a pacman hook).
- `enroll --disable-autologin` overrides SDDM autologin; `enroll --confirm-within N` auto-reverts unless you run `omarchy-identity confirm`; enrolment refuses unless a local account with a password exists.
- `omarchy-identity leave [--admin USER]` restores the pre-enrolment state and, with credentials, removes the computer account.

## What it deliberately does not do
Remove admin rights, push sudo rules, or harden boot (Secure Boot, TPM-bound LUKS). That's the MDM's job; an optional `managed` profile is planned. See [docs/DESIGN.md](docs/DESIGN.md).

## Packages
`omarchy-identity` (CLI, providers, hooks; `packaging/PKGBUILD`) and optional `omarchy-identity-shell` (a Quickshell bar widget showing posture; cosmetic only).

## Develop / test
See [CLAUDE.md](CLAUDE.md) for the dev loop and [test/README.md](test/README.md) for the lab (Samba AD in Docker + Arch VM under QEMU/KVM). [TODO.md](TODO.md) lists next work; [HANDOFF.md](HANDOFF.md) holds state and findings.
