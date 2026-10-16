# CLAUDE.md - omarchy-identity

Provider-agnostic corporate identity for Omarchy (Arch + Hyprland). Read `HANDOFF.md` (findings, state) and `TODO.md` (next work) before changing anything. Design: `docs/DESIGN.md`.

## Hard rules
- **Never test PAM/sssd/nsswitch/SDDM changes on the host.** The host is the owner's daily laptop; a bad PAM edit locks them out. Use the QEMU VM (`test/`).
- Never edit `/usr/share/omarchy/` (package-owned, overwritten by `omarchy update`). Use `/etc` drop-ins and markers.
- Enforcement lives in root-owned `/etc`. The shell widget is cosmetic, never a security boundary.
- Default is deny. Local break-glass accounts must keep working in every mode.
- Scope: this package does enrolment, login policy, posture reporting (`status --json`). Privilege removal (wheel), sudo rules, boot hardening are the MDM's job (an optional `managed` profile is planned, off by default).
- No AUR dependencies (adcli/oddjob are AUR-only; we use samba `net ads join` + `pam_mkhomedir`).
- Don't `pkill -f` (kills your own shell). Don't commit `test/vm/images`, `test/vm/keys`.

## Layout
    bin/omarchy-identity        core CLI: status [--json] | enroll <provider> | leave [--admin U] | reassert | providers
    providers/<name>/           detect enroll unenroll reassert status (+lib.sh). status prints key=value lines
    lib/common.sh, lib/posture.sh, lib/pamedit.py   shared helpers, read-only posture probes, idempotent BEGIN/END-marked PAM editor
    sddm-theme/omarchy-identity/    login theme = Omarchy's look + a username field (stock theme only logs in the last user)
    hooks/                      reassert.sh + post-update.d wrapper (re-apply edits after updates)
    packaging/                  PKGBUILD (omarchy-identity + omarchy-identity-shell), alpm hook, default config
    shell-plugin/               optional Quickshell bar widget (id omarchy-identity.status)
    test/dc  test/vm            Samba AD container + Arch QEMU client, e2e scripts
    docs/DESIGN.md POSTURE.md   architecture + security model; status --json schema
    test/unit                   no-VM unit tests (input validation)

## Provider contract
`providers/<name>/{detect,enroll,unenroll,reassert,status}` executables. They source `lib/common.sh`, use `$OI_ROOT` (set by the CLI), write state to `/etc/omarchy-identity/config.toml` (flat `key = "value"`), back up originals to `/var/lib/omarchy-identity/backup`. `enroll` must roll back fully on failure and must verify the directory works BEFORE touching PAM. `unenroll` must restore the pre-enrolment state exactly.

## Dev loop
    cd test/dc && docker compose up -d && ./seed-users.sh
    (cd test/vm && (setsid ./run.sh </dev/null >vm.log 2>&1 &))     # first boot: cloud-init, ~1 min
    test/vm/deploy.sh                 # push repo to VM (add --fixtures to reset PAM to stock Omarchy)
    test/run-all.sh        # every suite (~12 min); or run test/vm/e2e*.sh individually, each prints RESULT: ALL PASS
    # suites: e2e (enrol/policy/drift/leave) modes services dns offline package safety
    # DNS lab: test/dc/fix-dns.sh points the DC's A record at 10.0.2.2 (QEMU host address)
    bash hooks/test-reassert.sh; bash shell-plugin/tests/run.sh
VM: `ssh -i test/vm/keys/id_oi -p 2222 tester@127.0.0.1`. Lab creds (throwaway, loopback): Administrator/alice/bob/carol, password `Passw0rd!Test`.
Run e2e at least twice after touching enroll/unenroll: failures have been order-dependent (fresh vs pre-existing computer account).

## Conventions
- Anything the CLI sources must also be installed by `packaging/PKGBUILD` (e2e-package.sh catches misses).
- Bash with `set -euo pipefail`; quote everything; no new runtime deps without updating PKGBUILD.
- Any new PAM edit goes through `lib/pamedit.py` (markers, computed skip counts) and needs a remove/idempotency check.
- When you learn something non-obvious, add it to HANDOFF.md "Hard-won findings".
- Commit trailers per the session attribution rules.
