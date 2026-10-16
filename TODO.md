# TODO (priority order)

Legend: [ ] open, size S/M/L. Update this file as you go; put lessons in HANDOFF.md.

## P0 - before this touches a real machine
- [~] **Omarchy-like test VM (M).** DONE: Omarchy's real PAM services (sddm, sudo, login, sshd, system-remote-login, lock) + SDDM conf fixtures, session open + home-dir creation tested (`test/vm/e2e-services.sh`). REMAINING: a truly graphical check (SDDM greeter + Hyprland + the Omarchy lock screen's Quickshell PamContext) needs a VM with a GPU/virtio-gpu display; only this proves the greeter/lock UX. Also `polkit-1` PAM service is absent on this Omarchy (falls to `other`): check polkit auth as AD user.
- [x] **Autologin handling.** `--disable-autologin` writes `/etc/sddm.conf.d/zz-omarchy-identity.conf` (must sort AFTER Omarchy's `autologin.conf`); `status` reports the *effective* setting; `reassert` keeps it; `leave` restores. Tested.
- [x] **Lockout safety net.** `enroll` refuses unless a local account with a usable password exists (`--allow-no-local-fallback` overrides); `--confirm-within N` schedules an auto-revert (systemd transient timer) until `omarchy-identity confirm`. Tested (`test/vm/e2e-safety.sh`).

- [x] **Greeter username field (found late, important).** Omarchy's SDDM theme has NO username box (it logs in `userModel.lastUser`), so directory users could never sign in at the greeter. Added `sddm-theme/omarchy-identity` (Omarchy look + editable username), selected by `enroll` via `zz-omarchy-identity-theme.conf` (`--keep-login-theme` opts out), packaged, self-healed, reported in `status` (`login_theme`, `username_field`). Rendered and compared against stock via `sddm-greeter-qt6 --test-mode` + `grim`. REMAINING: verify in a real SDDM session (keyboard focus/Tab/Enter flow, failed-login shake state, multi-monitor), and consider upstreaming a username field to Omarchy's theme.

## P1 - make it usable
- [x] **Hook/package test.** Real package built+installed in the VM; a `pambase` pacman transaction triggers the alpm hook and repairs PAM + nsswitch (`test/vm/e2e-package.sh`). NOTE: pacman keeps modified `backup=` files and writes `.pacnew`, so the realistic drift sources are `omarchy update` migrations and manual edits, not plain package upgrades.
- [x] **Self-heal + hooks.** Root-owned `omarchy-identity-reassert.path` re-asserts PAM/nsswitch/SDDM edits within seconds of any change (started by enroll, stopped first by leave; flock serializes). `install-hooks` / `remove-hooks` for the per-user Omarchy post-update hook (it runs as the user and uses `sudo -n`; the path unit is the tamper-resistant mechanism). REMAINING: verify against a real `omarchy update` run on an Omarchy box (migrations like increase-lockout-limit.sh edit system-auth with sed).
- [x] **DNS discovery.** `--server` optional; krb5/samba/sssd use SRV records (`test/vm/e2e-dns.sh`; lab DNS via `test/dc/fix-dns.sh`). Still TODO: AD sites, multiple DCs/failover test, DNS-update (`--no-dns-updates` is set).
- [x] **Offline login.** Cached credentials work with the DC down; never-signed-in users are refused; recovery when the DC returns (`test/vm/e2e-offline.sh`). `--offline-days N` sets `offline_credentials_expiration` (config verified by `sssctl config-check`; actual expiry not time-tested).
- [x] **Non-interactive enrolment.** `--password-file` / `OI_ADMIN_PASSWORD_FILE` (0600, regular file, owned by root/caller) for enroll and leave (`test/vm/e2e-noninteractive.sh`). REMAINING: `--json` result, documented exit codes, an Ansible role snippet in docs/.
- [ ] **Config file parsing (S).** Replace flat sed parsing in `lib/common.sh` with a stricter reader (escaping, lists) or an env-style file.
- [x] **Password change.** `password` stack edit; directory user changes AD password via `passwd` (must run as the user: pam_sss refuses root resets), local users unaffected (`test/vm/e2e-passwd.sh`). Expired/must-change flow tested (`test/vm/e2e-expired.sh`): login is refused with a clear reason and `passwd` fixes it. REMAINING: the SDDM greeter has no change-password dialog (users need a TTY/SSH): add one to the identity theme; password-policy messages.
- [x] **Input validation.** realm/server/admin/groups/users/confirm validated before they reach sssd.conf/smb.conf/krb5.conf (`test/unit/validation.sh`). REMAINING: conf_write value escaping for the flat config file.
- [ ] **GPO access control (M).** `ad_gpo_access_control = disabled` is a lab shortcut; support `enforcing`/`permissive` with service mapping for sddm/lock/sudo.
- [x] **sudo for directory groups.** `--sudo-groups` -> visudo-validated `/etc/sudoers.d/50-omarchy-identity` (`test/vm/e2e-sudo.sh`). REMAINING: per-command rules, NOPASSWD option, sssd-native sudo provider (centrally managed rules).
- [ ] **Fresh-account join quirk (S, low priority).** Investigated: the only attribute change between join 1 and join 2 is `pwdLastSet` (msDS-SupportedEncryptionTypes=28 both times), so it's about how/when the new account's keys become usable by sssd on the *Samba* KDC, not a missing attribute. The double join is harmless. Still to try: `net ads changetrustpw -S srv` instead of a second join; check whether a real Windows AD DC shows the quirk at all (it may be Samba-only).
- [ ] **`su` and polkit (S).** `su` uses pam_unix directly (directory users can't `su`); Omarchy has no `polkit-1` PAM service (falls to `other`) - check polkit auth as a directory user.

- [x] **Compliance check.** `omarchy-identity check [--json]` evaluates `/etc/omarchy-identity/policy.toml` against the posture (exit 0/1/2), strict parser (typos are errors); 25 unit tests (`test/unit/check.sh`) + packaged test. REMAINING: more rules (pending updates, password age, local accounts with no password, fingerprint/smartcard policy), per-rule severity, signed/centrally pulled policies.

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
