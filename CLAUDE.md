# CLAUDE.md - monarchy-identity

Corporate identity for Omarchy (Arch + Hyprland): enrol in a directory, control who signs in, repair drift, report
posture. Read [TODO.md](TODO.md) (next work) before changing anything.

## Where things are documented
| Doc | For |
|---|---|
| `README.md`, `docs/ADMIN.md`, `docs/POSTURE.md` | Fleet admins (the audience). Keep in sync with behaviour changes. Screenshots in `docs/img/` |
| `docs/dev/DESIGN.md` | Architecture, scope, provider contract, files we touch |
| `docs/dev/TESTING.md` | The VM/DC lab and how to run suites |
| `docs/dev/FINDINGS.md` | Hard-won findings. **Add non-obvious lessons here.** |
| `TODO.md` | Open work, priority order |

## Hard rules
- **Never test PAM/sssd/nsswitch/SDDM changes on the host.** It's the owner's daily laptop; a bad PAM edit locks them out. Use the QEMU VM (`test/`).
- Never edit `/usr/share/omarchy/` (package-owned). Use `/etc` drop-ins and markers.
- Enforcement lives in root-owned `/etc`. The shell widget is cosmetic, never a security boundary.
- Default is deny. Local break-glass accounts must keep working in every mode.
- Scope: enrolment, login policy, posture reporting. Privilege removal (wheel), sudo rules and boot hardening are the MDM's job.
- No AUR dependencies (we use samba `net ads join` + `pam_mkhomedir`).
- Don't `pkill -f` (kills your own shell). Don't commit `test/vm/images`, `test/vm/keys`.

## Layout
    bin/monarchy-identity   core CLI
    providers/<name>/       detect enroll unenroll reassert status (+lib.sh); status prints key=value lines
    lib/                    common.sh, posture.sh (read-only probes), pamedit.py (idempotent BEGIN/END PAM editor)
    sddm-theme/             login theme: Omarchy's look + a username field
    hooks/                  reassert.sh + post-update wrapper
    packaging/              PKGBUILD (monarchy-identity + -shell), alpm hook, default config
    shell-plugin/           optional Quickshell bar widget (id monarchy-identity.status)
    test/                   dc (Samba AD container), vm (Arch QEMU client), unit
    docs/                   admin + user docs; docs/dev for contributors

## Dev loop (details in docs/dev/TESTING.md)
    cd test/dc && docker compose up -d && ./seed-users.sh
    (cd test/vm && (setsid ./run.sh </dev/null >vm.log 2>&1 &))
    test/vm/deploy.sh                  # push repo to VM
    test/run-all.sh                    # every suite; each prints RESULT: ALL PASS
    bash test/unit/*.sh; bash hooks/test-reassert.sh; bash shell-plugin/tests/run.sh
Run e2e at least twice after touching enroll/unenroll (failures have been order-dependent).

## Conventions
- Bash with `set -euo pipefail`; quote everything; no new runtime deps without updating PKGBUILD.
- Anything the CLI sources must also be installed by `packaging/PKGBUILD` (`e2e-package.sh` catches misses).
- Provider contract: `enroll` verifies the directory works BEFORE touching PAM and rolls back fully on failure; `unenroll` restores the pre-enrolment state exactly.
- Restart sssd ONLY via `sssd_restart`; never call `sssctl` without `</dev/null` + `timeout`.
- Every PAM rule we add must be `-`-prefixed and safe when `pam_sss.so` is missing, go through `lib/pamedit.py`, and have a remove/idempotency check.
- Test inputs that go through ssh must be `printf %q`-quoted; use `grep -F` for computer names.
- Commit trailers per the session attribution rules.
