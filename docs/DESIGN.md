# omarchy-identity

Provider-agnostic corporate identity for Omarchy.

## Packaging
- `omarchy-identity` (PKGBUILD in `packaging/`): CLI, providers, /etc defaults, post-update hook. Root-installed,
  works without the Omarchy shell (SDDM, SSH, headless enrolment).
- `omarchy-identity-shell`: optional status widget.

## Layers
1. Provider adapters (`providers/<name>/`): manifest.toml + detect, enroll, unenroll, status.
2. Core CLI (`bin/omarchy-identity`): enroll | status | leave. Applies adapter, writes
   root-owned drop-ins in /etc (never edits /usr/share/omarchy), backs up, supports rollback.
3. Optional UI package `omarchy-identity-shell` (`shell-plugin/`): Quickshell bar widget, cosmetic only.
   Depends on the CLI; the CLI never depends on it.

## Security model
- Enforcement lives in root-owned /etc (PAM, NSS, SDDM drop-ins, sssd.conf).
- Managed mode: daily user is NOT in wheel; break-glass local admin; autologin disabled.
- Boot chain (Secure Boot + TPM-bound LUKS + Limine password) is documented, applied separately.
- Dev mode: same CLI, no lockdown.
- Tamper-evident: `status` reports drift; post-update hook re-asserts drop-ins.

## Login policy (`login.mode`)
- assigned: listed users only
- groups: members of listed directory groups
- any: whole directory (explicit opt-in)
Default deny. Local break-glass admin always allowed.

## Drop-ins (survive `omarchy update`)
- /etc/sddm.conf.d/50-identity.conf (overrides autologin.conf)
- /etc/sssd/conf.d/*.conf
- /etc/omarchy-identity/config.toml (root:root 0644)

## Testing
QEMU/KVM Omarchy-like client VM + Samba AD or FreeIPA container on host. Never first-test PAM on a daily driver.
