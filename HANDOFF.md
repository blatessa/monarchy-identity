
> New here? Start with CLAUDE.md (rules + dev loop), then TODO.md. This file is the running log of state and findings.
# HANDOFF - read this first when resuming

Project: provider-agnostic corporate identity for Omarchy. Design in docs/DESIGN.md. Test env in test/README.md.
Owner: the repo owner. Do NOT test PAM/sssd changes on the owner's own laptop (the host); only in the QEMU VM.

## Decisions made (don't re-litigate)
- System package `monarchy-identity` (CLI + providers + /etc drop-ins + post-update hook) is the product.
  Shell plugin (`shell-plugin/`) is optional cosmetic UI, built LAST.
- MDM owns privilege removal/boot hardening. We own: enrolment, login policy (login.mode), posture
  reporting (`monarchy-identity status --json`). Optional `managed` profile later.
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
- Core CLI `bin/monarchy-identity`: status [--json] (incl. provider details), enroll, leave [--admin U], reassert, providers.
- sssd provider (`providers/sssd/{enroll,unenroll,reassert,status,detect,lib.sh}`), AD via samba `net ads join` + sssd.
  login.mode groups|assigned|any all tested; carol (directory-only) denied under groups/assigned; local user always works.
- `lib/pamedit.py`: idempotent BEGIN/END-marked pam_sss edit of /etc/pam.d/system-auth and omarchy-lock-password
  (skip counts computed from the file, safe next to Omarchy's pam_systemd_home lines). `remove` restores byte-identical.
- Drift: `status` reports pam_*=false when pambase etc. clobber PAM; `reassert` fixes it (tested).
- Packaging (`packaging/PKGBUILD`, alpm hook, `hooks/reassert.sh`, `hooks/post-update.d/`, `hooks/test-reassert.sh`): builds (checked with makepkg in a scratch copy).
- Shell widget `shell-plugin/` (id monarchy-identity.status): lint+model tests pass; NEVER loaded in a real shell yet.

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

## Session 2 additions (all tested in VM)
- Services matrix (sddm, sudo, login, sshd, system-remote-login) incl. session open + pam_mkhomedir (home 0700). All services funnel into system-auth, so one edit covers them. `su` uses pam_unix directly (AD users can't `su`; root `su` always works via pam_rootok).
- SDDM drop-ins merge in C-locale filename order, last wins; Omarchy's autologin.conf sorts after `99-*`, so our override is `zz-monarchy-identity.conf`. `status` autologin = effective value.
- Safety: local-fallback precondition + `--confirm-within` auto-revert timer + `confirm`. status has `revert_pending`.
- e2e tests share faillock state in the VM; reset faillock AFTER enrol (before enrol, directory users don't resolve and the reset is a silent no-op).
- Tooling gotcha: when patching scripts with python `s.index(...)`, make sure you match the intended occurrence (a duplicate-match once duplicated a whole test file).

- Self-heal: `monarchy-identity-reassert.path` (packaged in /usr/lib/systemd/system, enabled by enroll, disabled FIRST by leave) + flock in the CLI prevent the watcher from re-adding edits during leave. Plain pacman upgrades keep modified `backup=` files (.pacnew), so real drift comes from migrations/manual edits.
- `omarchy-hook` runs as the invoking USER from ~/.config/omarchy/hooks; `omarchy update` keeps sudo alive, so the hook uses `sudo -n`. Users can delete it: the path unit is the tamper-resistant mechanism.
- pam_sss refuses password changes initiated by root ("Password reset by root is not supported"): test as the user. Real `passwd` is setuid-root with the caller's real uid.
- Lab DNS: `test/dc/fix-dns.sh` (A record -> 10.0.2.2); VM resolves ~corp.test via systemd-resolved drop-in (set by e2e-dns.sh). DNS-discovery enrol works without --server.

- Rollback bug fixed: `enroll` rolled back via an ERR trap, but `die` calls `exit` (ERR never fires), so verification failures left sssd running + nsswitch edited. Now an EXIT trap with an `enrolled_ok` flag; it also deletes the just-created AD computer account (admin password is kept until success). `test/vm/e2e-failure.sh` snapshots PAM/nsswitch/services/config and proves failed enrolments change nothing.
- Greeter: Omarchy's SDDM theme has no username field -> `sddm-theme/monarchy-identity` (selected by enroll). Test mode render: `sddm-greeter-qt6 --test-mode --theme DIR` + `grim` works on the host without touching system config.
- Anything the CLI sources must be installed by PKGBUILD (posture.sh was missed once; e2e-package.sh catches it).

- Real greeter testing: Omarchy's SDDM greeter runs inside Hyprland; the VM uses SDDM's X11 greeter instead (same theme QML, same daemon, same PAM). `test/vm/qmon.py` (HMP socket: sendkey, screendump->PNG) + `e2e-greeter.sh`. `loginctl terminate-session` makes SDDM treat the helper as crashed and NOT restart the greeter: end test sessions by letting the session script exit.
- Test-fixture traps hit while building it (all were test bugs, not product bugs): samba-tool `group addmembers a,b` rejects the whole call if any is already a member (seed per member, now verified loudly); a file created by one user in a shared dir isn't writable by another (mode 644; plus fs.protected_regular in sticky /tmp) - use a world-writable non-sticky dir; SDDM logs failed logins with `user ""`.
- Always print diagnostics on a failing e2e step (diag() in e2e-greeter.sh): it turned a long guessing session into one run.

## Open items / next steps (priority order)
1. Smoke-test on a real Omarchy install is NOT done: SDDM greeter login of an AD user, hyprlock unlock as AD user,
   `sudo` as AD user, home-dir creation via pam_mkhomedir in a graphical session. VM is stock Arch w/o SDDM/Hyprland.
   Consider an Omarchy-like VM (install sddm + the fixtures) before touching the real laptop.
2. (DONE, see TODO.md) Autologin: Omarchy's autologin.conf logs in one fixed local user; override via /etc/sddm.conf.d/zz-monarchy-identity.conf
   disabling autologin (+ `managed` profile: remove wheel, break-glass admin). Not implemented. Core CLI only *reports* autologin.
3. Wire the post-update hook install: `omarchy hook install post-update hooks/post-update.d/10-monarchy-identity-reassert`
   (Omarchy hooks are per-user ~/.config/omarchy/hooks; alpm hook covers system-level upgrades). Test with a simulated pambase upgrade.
4. Run hooks/test-reassert.sh and widget tests/run.sh again after any CLI change; try widget in real shell (see shell-plugin/README.md).
5. DNS-based discovery (production): lab uses /etc/hosts + explicit --server. Support omitting --server (SRV lookup), AD sites.
6. Password change (`passwd` as AD user) PAM edit not done; ad_gpo_access_control is disabled (revisit); offline-login test.
7. oidc provider (Entra/Okta/Google via authd/himmelblau) = empty dir. IPA/LDAP variants of sssd. Provider contract is
   detect/enroll/unenroll/status/reassert scripts under providers/<name>/ (status prints key=value lines).
8. PKGBUILD url/license placeholders; shell package name check; config.toml parsing is flat key="value" only.
9. Do not test on the host /etc until (1) is done. The host is the owner's daily-driver laptop.

## Quick start for a new session
    cd test/dc && docker compose up -d && ./seed-users.sh     # if DC down
    test/vm/run.sh   (run backgrounded: (setsid ./run.sh </dev/null >log 2>&1 &))   # if VM down; first run installs via cloud-init
    test/vm/e2e.sh && test/vm/e2e-modes.sh                    # expect ALL PASS
