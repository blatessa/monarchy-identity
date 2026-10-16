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

## Status
(see bottom; update as you go)
- [x] core CLI + local provider
- [x] test env (DC + VM, reachable on 389/88)
- [ ] sssd provider (in progress)
