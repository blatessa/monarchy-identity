# AGENTS.md

Guidance for coding agents (and humans) working in this repo. Keep it short and accurate; update it when reality changes.

## What this is
`monarchy-identity` is a single-purpose utility: it connects an Omarchy (Arch + Hyprland) machine's authentication to a
directory (Active Directory / Samba AD via sssd) and keeps that working. Enroll, decide who may sign in (and who gets
sudo), survive updates, leave. Other tools (MDMs, agents) build on it through the CLI and `status --json`; it is not a
platform and doesn't manage the device. It edits PAM, nsswitch, SDDM and sudoers, so mistakes lock people out.
Status: prototype, verified only in a VM against Samba AD. Public docs are the MkDocs site in `docs/`.

## Before you change anything
1. Read the hard rules below. Run `test/lab-check.sh` if the task needs the lab.
2. Skim `docs/dev/` (`architecture.md`, `testing.md`, `findings.md`) for the area you're touching. `findings.md` lists traps already hit.
3. Open work is GitHub issues: a queue for agents (see "Picking work" below). Pick or create an issue first.

## Hard rules
- **Never test PAM/sssd/nsswitch/SDDM changes on the host machine.** A bad PAM edit locks the owner out. Use the QEMU VM lab (`test/`).
- Never edit `/usr/share/omarchy/` (package-owned, overwritten by `omarchy update`). Use `/etc` drop-ins and markers.
- Enforcement lives in root-owned `/etc`. The shell widget is cosmetic, never a security boundary.
- Default is deny. Local accounts must keep working when sssd or `pam_sss.so` is missing or broken (that's PAM correctness, not an undo feature).
- **Scope is authentication.** Enrollment, who may sign in, directory-provided authorization (sudo groups, offline lifetime, later GPO), keeping it working across updates, `leave`. No device posture/compliance, inventory, hardening, tamper resistance or undo machinery (timers, backups, rollback): that's the MDM's or the deployer's job. Test: would it belong in a plain Linux directory client? See `docs/dev/architecture.md#scope`.
- No AUR dependencies (join with samba `net ads join`; home dirs via `pam_mkhomedir`).
- Don't `pkill -f` (it kills your own shell); find processes by PID. Don't commit `test/vm/images`, `test/vm/keys`, credentials or real hostnames.
- Don't publish, tag, force-push or change repo settings without the owner asking.

## Layout
    bin/monarchy-identity    core CLI (status|enroll|leave|policy|reassert|install-hooks|install-widget|providers)
    providers/<name>/        enroll unenroll policy reassert status detect (+lib.sh); `status` prints key=value lines
    lib/                     common.sh, pamedit.py (idempotent BEGIN/END-marked PAM editor)
    sddm-theme/              login theme: Omarchy's look + a username field (stock theme only logs in the last user)
    hooks/                   reassert.sh + post-update wrapper
    packaging/               PKGBUILD (monarchy-identity + -shell), alpm hook, install scriptlet, default config
    shell-plugin/            optional Quickshell bar widget (id monarchy-identity.status)
    test/                    dc (Samba AD container), vm (Arch QEMU client, lib.sh + e2e suites), unit
    docs/                    MkDocs site (user-facing docs + developer pages)
    .github/workflows/       ci.yml, release.yml, docs.yml

## Commands
Prerequisites for the lab: Docker, QEMU/KVM + OVMF, ssh, python3, node (widget tests). Details: `docs/dev/testing.md`.

    test/lab-check.sh                 # prerequisites + lab state; prints the exact fix for anything missing
    bash test/unit/validation.sh; bash test/unit/naming.sh                             # no lab needed, seconds
    bash hooks/test-reassert.sh; bash shell-plugin/tests/run.sh                        # no lab needed
    cd test/dc && docker compose up -d && ./seed-users.sh                              # directory
    (cd test/vm && ./fetch-image.sh && (setsid ./run.sh </dev/null >vm.log 2>&1 &))   # VM; makes its own ssh key; first boot ~1 min
    test/vm/deploy.sh [--fixtures]    # push repo to the VM (--fixtures resets PAM to stock Omarchy, removes the package)
    test/vm/e2e*.sh                   # one suite; each prints RESULT: ALL PASS
    test/run-all.sh                   # everything
    ssh -i test/vm/keys/id_oi -p 2222 tester@127.0.0.1                                 # the VM
Lab credentials are throwaway and loopback-only: Administrator/alice/bob/carol, password `Passw0rd!Test`.

## Definition of done
- Unit tests pass; for anything touching enroll/unenroll/PAM/sssd/SDDM, the relevant e2e suites pass in the VM.
  Suites must not depend on what ran before them: start from `fresh`, and cover a fresh vs an existing computer
  account explicitly rather than by re-running.
- `enroll` checks everything the directory can reject before it changes sign-in; `leave` removes every change enroll made.
- New PAM edit: goes through `lib/pamedit.py`, rule is `-`-prefixed, safe when `pam_sss.so` is missing, has a remove/idempotency test.
- Anything the CLI sources is also installed by `packaging/PKGBUILD` (`test/vm/e2e-package.sh` catches misses).
- **Docs considered.** Ask "does a user or admin see this change?" Not every change needs a docs edit, but decide deliberately, and say in the commit/PR what you did ("docs: updated X" or "docs: none, internal"). See the map below. Run `mkdocs build --strict` when you touch `docs/` (CI does too).
- A non-obvious lesson goes into `docs/dev/findings.md`.
- CI is green (`gh run list`).

## Which docs does a change touch?
| You changed | Update |
|---|---|
| CLI command, flag, output, exit code (`bin/`, `providers/*/enroll`) | `docs/reference/cli.md`, and the guide that uses it |
| `status --json` fields (`bin/`, `providers/*/status`) | `docs/reference/status-output.md` |
| How sign-in behaves for people, login policy | `docs/concepts/*` |
| Rollout advice, operating the fleet | `docs/guides/*` |
| Files we write, enroll order, PAM, scope decisions | `docs/dev/architecture.md` (not the user guide) |
| Provider behaviour or a new provider | `docs/providers/*` (user view), `docs/dev/writing-a-provider.md` |
| Verified/unverified status, known limits | `docs/status.md` |
| Lab, test, release workflow | `docs/dev/testing.md` |
| Internal only (refactor, test-only) | usually nothing |

## Conventions
- Bash with `set -euo pipefail`; quote everything; no new runtime deps without updating PKGBUILD.
- Provider contract: `enroll` checks everything the directory can reject before joining and edits PAM last; a re-run picks up after a failure (no rollback machinery). `unenroll` removes every change enroll made. State goes in `/etc/monarchy-identity/config.toml` (flat `key = "value"`). See `docs/dev/writing-a-provider.md`.
- Restart sssd ONLY via `sssd_restart` (systemd start-limit). Never call `sssctl` without `</dev/null` and `timeout` (it can prompt and hang, holding the CLI flock).
- Test inputs that go through ssh must be `printf %q`-quoted; use `grep -F` for computer names (`$` is a regex anchor).
- **Defaults over configuration; don't expose implementation.** The person using this is an administrator, not a
  maintainer. A good behaviour should be the default (or implied by what they already said), not a flag they must
  know about. The user docs are a guide: name things in their terms (sign-in, laptop, group); `pam_*`, file paths,
  units and sssd details go in `docs/dev/`, and only when they explain a decision or a trap (don't restate the code).
  A new option needs a reason a default can't cover.
- Match the surrounding code's style and comment density. Small, focused commits; explain why in the message.

## Skills (project procedures, load on demand)
`.claude/skills/`: `lab-e2e` (run and debug the lab), `pam-change` (checklist for any system-config edit), `new-provider`, `release`.

## Picking work
GitHub issues are the work queue for agents. Labels: `P0` (blocks real use) to `P3` (polish), and `needs-lab` (needs
the VM/DC lab to verify). Take the highest-priority open issue without an assignee or open PR; each issue body says
what done looks like. Close it from the PR (`Fixes #N`). If you find new work, open an issue in the same shape rather
than expanding the current change.

## Workflow
Branch from `main`, open a PR, let CI run; releases are cut by tagging `vX.Y.Z` (see the `release` skill; the tag must match `pkgver`).
Security issues: private advisory (see `SECURITY.md`), not a public issue.
