# monarchy-identity

Provider-agnostic corporate identity for Omarchy.

## Packaging
- `monarchy-identity` (PKGBUILD in `packaging/`): CLI, providers, /etc defaults, post-update hook. Root-installed,
  works without the Omarchy shell (SDDM, SSH, headless enrolment).
- `monarchy-identity-shell`: optional status widget.

## Layers
1. Provider adapters (`providers/<name>/`): manifest.toml + detect, enroll, unenroll, status.
2. Core CLI (`bin/monarchy-identity`): enroll | status | leave. Applies adapter, writes
   root-owned drop-ins in /etc (never edits /usr/share/omarchy), backs up, supports rollback.
3. Optional UI package `monarchy-identity-shell` (`shell-plugin/`): Quickshell bar widget, cosmetic only.
   Depends on the CLI; the CLI never depends on it.

## Scope and security model
- This package owns: directory enrolment, login policy, posture reporting.
- Privilege removal (no wheel), sudo rules, boot hardening belong to the org's MDM/config mgmt.
- `monarchy-identity status --json` is the integration point: enrolled, provider, login.mode,
  autologin off, drop-in drift, local wheel members. MDM/osquery/Ansible read it for compliance.
- Optional `managed` profile (off by default) applies hardening for orgs with no MDM:
  remove wheel, disable autologin, break-glass admin, boot-chain guidance.
- Enforcement lives in root-owned /etc; the shell plugin is cosmetic, never a boundary.
- Tamper-evident: status reports drift; post-update hook re-asserts drop-ins.

## Login policy (`login.mode`)
- assigned: listed users only
- groups: members of listed directory groups
- any: whole directory (explicit opt-in)
Default deny. Local break-glass admin always allowed.

## Drop-ins (survive `omarchy update`)
- /etc/sddm.conf.d/zz-monarchy-identity.conf (overrides autologin.conf)
- /etc/sssd/conf.d/*.conf
- /etc/monarchy-identity/config.toml (root:root 0644)

## Testing
QEMU/KVM Omarchy-like client VM + Samba AD or FreeIPA container on host. Never first-test PAM on a daily driver.
