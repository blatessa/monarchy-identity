# TODO (priority order)

Legend: [ ] open, size S/M/L. Update this file as you go; put lessons in HANDOFF.md.

## P0 - before this touches a real machine
- [~] **Omarchy-like test VM (M).** DONE: Omarchy's real PAM services (sddm, sudo, login, sshd, system-remote-login, lock) + SDDM conf fixtures, session open + home-dir creation tested (`test/vm/e2e-services.sh`). REMAINING: a truly graphical check (SDDM greeter + Hyprland + the Omarchy lock screen's Quickshell PamContext) needs a VM with a GPU/virtio-gpu display; only this proves the greeter/lock UX. Also `polkit-1` PAM service is absent on this Omarchy (falls to `other`): check polkit auth as AD user.
- [x] **Autologin handling.** `--disable-autologin` writes `/etc/sddm.conf.d/zz-omarchy-identity.conf` (must sort AFTER Omarchy's `autologin.conf`); `status` reports the *effective* setting; `reassert` keeps it; `leave` restores. Tested.
- [x] **Lockout safety net.** `enroll` refuses unless a local account with a usable password exists (`--allow-no-local-fallback` overrides); `--confirm-within N` schedules an auto-revert (systemd transient timer) until `omarchy-identity confirm`. Tested (`test/vm/e2e-safety.sh`).

## P1 - make it usable
- [ ] **Hook installation (S).** `omarchy-identity install-hooks` (per-user `omarchy hook install post-update ...`); simulate a `pambase` upgrade (rewrite stock `system-auth`) in the VM and confirm the alpm hook repairs it.
- [ ] **DNS discovery (M).** Make `--server` optional (SRV lookup, AD sites), production-style DNS instead of the lab's `/etc/hosts`.
- [ ] **Non-interactive enrolment (S).** `--password-file` / env, JSON output, exit codes, so MDM/Ansible can run it. Document an Ansible role snippet.
- [ ] **Config file parsing (S).** Replace flat sed parsing in `lib/common.sh` with a stricter reader (escaping, lists) or switch to a simple KEY=value env file.
- [ ] **Password change + offline login (M).** `passwd` for AD users (PAM `password` stack edit), cached-credential behaviour when the DC is unreachable; add to e2e (block the DC port in the VM).
- [ ] **GPO access control (M).** `ad_gpo_access_control = disabled` is a lab shortcut; support `enforcing`/`permissive` and the service-name mapping for sddm/hyprlock.
- [ ] **Root-cause the fresh-account join quirk (M).** Why a first `net ads join` keytab is rejected by sssd (kvno/salt). Try `net ads join` + `net ads keytab create` ordering, `sync machine password to keytab`, or sssd's own join. Drop the double-join if fixed.

## P2 - more providers and profiles
- [ ] **OIDC provider (L).** Entra ID / Okta / Google Workspace (candidates: `himmelblau` for Entra, `authd`); decide if packages come from AUR (conflicts with the no-AUR rule) and how to handle that.
- [ ] **FreeIPA / generic LDAP+Kerberos provider (M).** Reuse most of the sssd provider; add a FreeIPA container to `test/dc`.
- [ ] **`managed` profile (M).** Opt-in hardening: remove wheel, break-glass admin, disable autologin, sbctl Secure Boot + TPM2-bound LUKS guidance. Off by default; MDM may own it instead.
- [ ] **Posture schema (S).** Version and document `status --json`; add provider-independent compliance fields (disk encryption, firewall, screen-lock timeout) so one report serves MDMs.

## P3 - polish
- [ ] **Widget in a real shell (S).** Load `shell-plugin/` into the live shell (see its README), fix glyph/sizing issues, add enrol/leave actions? (keep cosmetic).
- [ ] **Packaging (S).** Real `url`/`license`, `.install` scriptlet (no automatic enrolment), CI that builds the package and runs `hooks/test-reassert.sh`.
- [ ] **CI for the lab (M).** Script the full lab (DC + VM + e2e) so it runs headless on a CI box with KVM.
- [ ] **Upstream conversation (S).** Share the PAM-skip approach and the `omarchy-lock-password` finding with the Omarchy maintainers; ask for an official policy layer / drop-in dir.
