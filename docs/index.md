# monarchy-identity

monarchy-identity joins an [Omarchy](https://omarchy.org) laptop to a corporate directory so that directory users can
sign in. It also enforces who may sign in, repairs its own configuration if an update overwrites it, and reports
device posture for management tooling. It is the identity component of Monarchy, a set of tools for running Omarchy
as a work computer.

!!! warning "Prototype"
    Verified in a VM against Samba AD. Windows AD, FreeIPA, Entra ID, Omarchy's own Hyprland-based login screen and
    the Quickshell lock screen have not been tested. See [Status and limits](status.md). Pilot on machines you can
    recover.

## What it does

- Joins the machine to Active Directory (or Samba AD) with `net ads join` and configures sssd, Kerberos and
  nsswitch.
- Adds `pam_sss` to the PAM stacks used by the login screen, lock screen, `sudo`, `login` and `sshd` without
  changing how local accounts authenticate.
- Applies a default-deny [login policy](concepts/login-policy.md): members of listed groups, listed users, or the
  whole directory.
- Installs an SDDM theme with a username field, because Omarchy's stock theme logs in only the last user.
- Re-applies its edits when a package update or a person overwrites them ([self-healing](concepts/self-healing.md)).
- Reports posture as JSON (`status --json`) and evaluates it against a policy file (`check`).

## What it does not do

It does not remove admin rights from local users, manage sudo beyond an optional group mapping, harden the boot
chain, or manage fleet inventory. Use your MDM or configuration management for those; this tool reports on them.

## Where to start

| If you want to | Read |
|---|---|
| Enroll one machine and check that it works | [Getting started](getting-started.md) |
| Roll it out to a fleet | [Plan a rollout](guides/rollout-planning.md), then [Automate enrollment](guides/automation.md) |
| Look up a flag or a file | [CLI](reference/cli.md), [Files, units and variables](reference/files.md) |
| See the lab evidence that it authenticates against a directory | [Evidence from the lab](evidence.md) |
| Work on the code | [Architecture](dev/architecture.md), [Testing](dev/testing.md) |

Source: <https://github.com/blatessa/monarchy-identity>. MIT licensed.
