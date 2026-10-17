# monarchy-identity

Corporate sign-in for [Omarchy](https://omarchy.org), and the identity component of **Monarchy**, a management
suite that aims to make Omarchy a practical work computer.

Enrol a laptop in your company directory (Active Directory / Samba AD today; other providers are pluggable), control
who may sign in, keep that configuration from drifting, and report device posture to the management tooling you
already run. Directory users sign in at the normal Omarchy login screen, which gains a username box.

> **Status: prototype.** Verified end to end in a VM against Samba AD, including the real SDDM login screen (X11
> greeter). **Not yet verified:** Omarchy's own Hyprland-based greeter, the Quickshell lock screen, Windows AD,
> FreeIPA, Entra ID/OIDC. Pilot it on a few machines you can recover before rolling out.

## Rolling it out to a fleet

1. **Prepare the directory:** a join account with rights to create computer objects in one OU, an OU for laptops, and
   a security group for who may sign in (e.g. `laptop-users`).
2. **Build and publish the package** to your own pacman repo: `makepkg` in `packaging/`, then `repo-add`.
3. **Install on each laptop:** `sudo pacman -S monarchy-identity`. Nothing changes until you enrol.
4. **Enrol** (needs a unique hostname of at most 15 characters, and a local account with a password as fallback):

        sudo monarchy-identity enroll sssd --realm CORP.EXAMPLE.COM --admin joinuser \
             --ou 'OU=Laptops,DC=corp,DC=example,DC=com' \
             --mode groups --groups laptop-users --disable-autologin --confirm-within 10

   Sign in as a directory user, then run `sudo monarchy-identity confirm`. If you don't, the laptop reverts itself
   after 10 minutes.
5. **Automate it** with `--password-file` and `--if-needed` (Ansible example in the admin guide), and **monitor** with
   `monarchy-identity status --json` and `monarchy-identity check`.

![monarchy-identity status after enrolment](docs/img/status.png)

The full walk-through, with the reasoning and the failure modes, is the **[admin guide](docs/ADMIN.md)**.

## What it does

- **Enrol and join.** Joins the domain, starts sssd, and adds `pam_sss` to the login and lock-screen PAM stacks without
  disturbing local accounts. DCs are found through DNS (`--server` is optional).
- **Login policy.** `groups`, `assigned` (listed users) or `any` (whole directory, explicit opt-in). Default deny.
  Local break-glass accounts always work. Change it later with `policy set`, no re-join.
- **A login screen that works.** Omarchy's stock SDDM theme has no username box; enrolment selects a
  `monarchy-identity` theme with one.
- **Stays correct.** A root-owned systemd path unit repairs the PAM, nsswitch and SDDM edits within seconds if an update
  or a person overwrites them.
- **Fleet-safe.** Never takes over an existing computer account, refuses colliding hostnames, rolls back (including
  the directory account) on any failure. Broken sssd or a missing PAM module never locks out local users.
- **Reports and checks.** `status --json` is a versioned posture report (identity, disk encryption, firewall,
  Secure Boot, TPM2, lock timeout, clock sync); `check` evaluates it against a policy file and exits 0/1/2.
- **Optional extras.** `--sudo-groups`, `--offline-days`, `--disable-autologin`, offline login, and a Quickshell
  status widget (`monarchy-identity-shell`, cosmetic only).

## What it deliberately does not do

Remove admin rights from existing local users, enforce a device-wide privilege model, or harden boot. Those belong to
your MDM or other Monarchy components; this tool reports on them and leaves enforcement to you.

## Documentation

| You are... | Read |
|---|---|
| **An admin** rolling it out (start here) | [Admin guide](docs/ADMIN.md), [posture report schema](docs/POSTURE.md) |
| **A developer or coding agent** | [CLAUDE.md](CLAUDE.md), then [design](docs/dev/DESIGN.md), [testing](docs/dev/TESTING.md), [findings](docs/dev/FINDINGS.md), [TODO](TODO.md) |

[CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) (report vulnerabilities privately) · MIT, see [LICENSE](LICENSE).
