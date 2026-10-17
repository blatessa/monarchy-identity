# AGENTS.md

Guidance for coding agents (and humans) working in this repo. Keep it short and accurate; update it when reality changes.

## What this is
`monarchy-identity` enrols an Omarchy (Arch + Hyprland) laptop in a corporate directory (Active Directory / Samba AD
via sssd), enforces who may sign in, repairs configuration drift, and reports device posture (`status --json`).
It edits PAM, nsswitch, SDDM and sudoers, so mistakes lock people out. Status: prototype, verified only in a VM
against Samba AD. Public docs are the MkDocs site in `docs/` (published to GitHub Pages).

## Before you change anything
1. Read the hard rules below.
2. Skim `docs/` developer pages (architecture, testing, findings) for the area you're touching. `FINDINGS` lists traps already hit.
3. Open work is tracked as GitHub issues (`gh issue list`); `TODO.md` is only an index. Pick or create an issue first.

## Hard rules
- **Never test PAM/sssd/nsswitch/SDDM changes on the host machine.** A bad PAM edit locks the owner out. Use the QEMU VM lab (`test/`).
- Never edit `/usr/share/omarchy/` (package-owned, overwritten by `omarchy update`). Use `/etc` drop-ins and markers.
- Enforcement lives in root-owned `/etc`. The shell widget is cosmetic, never a security boundary.
- Default is deny. Local break-glass accounts must work in every mode and when sssd/`pam_sss.so` is missing or broken.
- Scope is enrolment, login policy, drift repair, posture reporting. Privilege removal (wheel), sudo policy and boot hardening belong to the MDM (an opt-in `managed` profile is planned, off by default).
- No AUR dependencies (join with samba `net ads join`; home dirs via `pam_mkhomedir`).
- Don't `pkill -f` (it kills your own shell); find processes by PID. Don't commit `test/vm/images`, `test/vm/keys`, credentials or real hostnames.
- Don't publish, tag, force-push or change repo settings without the owner asking.

## Layout
    bin/monarchy-identity    core CLI (status|enroll|leave|policy|check|confirm|reassert|install-hooks|install-widget|providers)
    providers/<name>/        detect enroll unenroll reassert status (+lib.sh); `status` prints key=value lines
    lib/                     common.sh, posture.sh (read-only probes), pamedit.py (idempotent BEGIN/END-marked PAM editor), check.py
    sddm-theme/              login theme: Omarchy's look + a username field (stock theme only logs in the last user)
    hooks/                   reassert.sh + post-update wrapper
    packaging/               PKGBUILD (monarchy-identity + -shell), alpm hook, systemd units, default config, policy example
    shell-plugin/            optional Quickshell bar widget (id monarchy-identity.status)
    test/                    dc (Samba AD container), vm (Arch QEMU client + e2e suites), unit
    docs/                    MkDocs site (user-facing docs + developer pages)
    .github/workflows/       ci.yml, release.yml, docs.yml

## Commands
Prerequisites for the lab: Docker, QEMU/KVM + OVMF, ssh, python3, node (widget tests). Details: developer testing page in `docs/`.

    bash test/unit/validation.sh; bash test/unit/naming.sh; bash test/unit/check.sh   # no lab needed, seconds
    bash hooks/test-reassert.sh; bash shell-plugin/tests/run.sh                        # no lab needed
    cd test/dc && docker compose up -d && ./seed-users.sh                              # directory
    (cd test/vm && ./fetch-image.sh && (setsid ./run.sh </dev/null >vm.log 2>&1 &))   # VM, first boot ~1 min
    test/vm/deploy.sh [--fixtures]    # push repo to the VM (--fixtures resets PAM to stock Omarchy, removes the package)
    test/vm/e2e*.sh                   # one suite; each prints RESULT: ALL PASS
    test/run-all.sh                   # everything, ~15 min
    ssh -i test/vm/keys/id_oi -p 2222 tester@127.0.0.1                                 # the VM
Lab credentials are throwaway and loopback-only: Administrator/alice/bob/carol, password `Passw0rd!Test`.

## Definition of done
- Unit tests pass; for anything touching enroll/unenroll/PAM/sssd/SDDM, the relevant e2e suites pass in the VM,
  and **e2e ran at least twice** (failures have been order-dependent: fresh vs pre-existing computer account).
- Failure paths leave the machine as found; `leave` restores the original files.
- New PAM edit: goes through `lib/pamedit.py`, rule is `-`-prefixed, safe when `pam_sss.so` is missing, has a remove/idempotency test.
- Anything the CLI sources is also installed by `packaging/PKGBUILD` (`test/vm/e2e-package.sh` catches misses).
- Docs updated for behaviour/flag changes (reference pages must match the code); a non-obvious lesson goes into the findings page.
- CI is green (`gh run list`).

## Conventions
- Bash with `set -euo pipefail`; quote everything; no new runtime deps without updating PKGBUILD.
- Provider contract: `enroll` verifies the directory works BEFORE touching PAM and rolls back fully on failure; `unenroll` restores the pre-enrolment state exactly. State goes in `/etc/monarchy-identity/config.toml` (flat `key = "value"`), originals in `/var/lib/monarchy-identity/backup`.
- Restart sssd ONLY via `sssd_restart` (systemd start-limit). Never call `sssctl` without `</dev/null` and `timeout` (it can prompt and hang, holding the CLI flock).
- Test inputs that go through ssh must be `printf %q`-quoted; use `grep -F` for computer names (`$` is a regex anchor).
- Match the surrounding code's style and comment density. Small, focused commits; explain why in the message.

## Workflow
Branch from `main`, open a PR, let CI run; releases are cut by tagging `vX.Y.Z` (see the testing/releasing page; the tag must match `pkgver`).
Security issues: private advisory (see `SECURITY.md`), not a public issue.
