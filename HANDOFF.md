# HANDOFF - read this first when resuming

Project: provider-agnostic corporate identity for Omarchy. Design in docs/DESIGN.md. Test env in test/README.md.
Owner: brady. Do NOT test PAM/sssd changes on the host (/etc of this laptop); only in the QEMU VM.

## Decisions made (don't re-litigate)
- System package `omarchy-identity` (CLI + providers + /etc drop-ins + post-update hook) is the product.
  Shell plugin (`shell-plugin/`) is optional cosmetic UI, built LAST.
- MDM owns privilege removal/boot hardening. We own: enrolment, login policy (login.mode), posture
  reporting (`omarchy-identity status --json`). Optional `managed` profile later.
- login.mode = assigned | groups | any. Default deny. Local break-glass admin always allowed.
- No AUR deps: join via samba `net ads join`, home dirs via pam_mkhomedir (adcli/oddjob are AUR-only).
- Use /etc drop-ins; never edit /usr/share/omarchy. Re-assert after `omarchy update` via post-update hook.
- First provider = sssd (AD/IPA). OIDC/Entra later (uncertain).

## Test env (see test/README.md)
- DC: `cd test/dc && docker compose up -d && ./seed-users.sh` (CORP.TEST, users alice/bob/carol, pw Passw0rd!Test)
- VM: `test/vm/run.sh` (background it, setsid); ssh -i test/vm/keys/id_oi -p 2222 tester@127.0.0.1
- Stop VM by PID (pgrep -x qemu-system-x86). NEVER `pkill -f` (kills own shell).
- VM is STOCK Arch, not Omarchy: PAM files differ. Copy Omarchy's /etc/pam.d files in to be faithful.

## Status (2026-10-16)
DONE and verified in the VM (run `test/vm/e2e.sh` and `test/vm/e2e-modes.sh`, both ALL PASS, e2e.sh passed 4x in a row from a fresh AD account):
- Core CLI `bin/omarchy-identity`: status [--json] (incl. provider details), enroll, leave [--admin U], reassert, providers.
- sssd provider (`providers/sssd/{enroll,unenroll,reassert,status,detect,lib.sh}`), AD via samba `net ads join` + sssd.
  login.mode groups|assigned|any all tested; carol (directory-only) denied under groups/assigned; local user always works.
- `lib/pamedit.py`: idempotent BEGIN/END-marked pam_sss edit of /etc/pam.d/system-auth and omarchy-lock-password
  (skip counts computed from the file, safe next to Omarchy's pam_systemd_home lines). `remove` restores byte-identical.
- Drift: `status` reports pam_*=false when pambase etc. clobber PAM; `reassert` fixes it (tested).
- Packaging (`packaging/PKGBUILD`, alpm hook, `hooks/reassert.sh`, `hooks/post-update.d/`, `hooks/test-reassert.sh`): builds (checked with makepkg in a scratch copy).
- Shell widget `shell-plugin/` (id brady.identity-status): lint+model tests pass; NEVER loaded in a real shell yet.

## Hard-won findings (do not rediscover)
- Omarchy lock screen uses its own PAM service /etc/pam.d/omarchy-lock-password (not package-owned, copy of auth stack). Must be edited too.
- Omarchy ships etc-overrides/nsswitch.conf; updates may reset `sss` -> reassert re-adds it.
- sssd, samba, krb5 are in Arch `extra`; adcli & oddjob are AUR-only (not used).
- DC discovery needs UDP 389 (CLDAP) published; samba commands need `-S <server>` when no DNS (the lab).
- FRESH computer account quirk: after the first `net ads join`, sssd (ldap_child) gets "Preauthentication failed"
  although `kinit -k` works; a SECOND join fixes it. enroll joins twice. Root cause not fully understood
  (kvno/key state of new accounts). Keytab must be built with `net ads keytab create -S srv -U admin` (NOT -P) after `rm -f /etc/krb5.keytab`.
- pam_faillock (deny=10) applies to directory users too; my own wrong-password tests locked alice. e2e resets faillock.
- `net ads leave` needs admin creds + -S to delete the AD computer account; without --admin it warns and leaves it.
- test/vm/deploy.sh WITHOUT --fixtures keeps current PAM files; WITH --fixtures resets /etc/pam.d to stock Omarchy (undoes edits).
- Don't use `pkill -f` (kills own shell); no sshpass/pamtester on Arch -> test/vm/trylogin.sh (SSH_ASKPASS) and pamtest.py (ctypes libpam).

## Open items / next steps (priority order)
1. Smoke-test on a real Omarchy install is NOT done: SDDM greeter login of an AD user, hyprlock unlock as AD user,
   `sudo` as AD user, home-dir creation via pam_mkhomedir in a graphical session. VM is stock Arch w/o SDDM/Hyprland.
   Consider an Omarchy-like VM (install sddm + the fixtures) before touching the real laptop.
2. Autologin: sddm autologin.conf (User=brady) conflicts with managed identity; add a drop-in /etc/sddm.conf.d/50-identity.conf
   disabling autologin (+ `managed` profile: remove wheel, break-glass admin). Not implemented. Core CLI only *reports* autologin.
3. Wire the post-update hook install: `omarchy hook install post-update hooks/post-update.d/10-omarchy-identity-reassert`
   (Omarchy hooks are per-user ~/.config/omarchy/hooks; alpm hook covers system-level upgrades). Test with a simulated pambase upgrade.
4. Run hooks/test-reassert.sh and widget tests/run.sh again after any CLI change; try widget in real shell (see shell-plugin/README.md).
5. DNS-based discovery (production): lab uses /etc/hosts + explicit --server. Support omitting --server (SRV lookup), AD sites.
6. Password change (`passwd` as AD user) PAM edit not done; ad_gpo_access_control is disabled (revisit); offline-login test.
7. oidc provider (Entra/Okta/Google via authd/himmelblau) = empty dir. IPA/LDAP variants of sssd. Provider contract is
   detect/enroll/unenroll/status/reassert scripts under providers/<name>/ (status prints key=value lines).
8. PKGBUILD url/license placeholders; shell package name check; config.toml parsing is flat key="value" only.
9. Do not test on the host /etc until (1) is done. Host = brady's daily Omarchy laptop.

## Quick start for a new session
    cd test/dc && docker compose up -d && ./seed-users.sh     # if DC down
    test/vm/run.sh   (run backgrounded: (setsid ./run.sh </dev/null >log 2>&1 &))   # if VM down; first run installs via cloud-init
    test/vm/e2e.sh && test/vm/e2e-modes.sh                    # expect ALL PASS
