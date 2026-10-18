# AGENTS.md

Guidance for coding agents (and humans) working in this repo. Keep it short and accurate; update it when reality changes.

## What this is
`monarchy-identity` is a single-purpose utility: it connects an Omarchy (Arch + Hyprland) machine's authentication to a
company directory and keeps that working. Directories plug in as providers: Active Directory (`providers/ad`, via
samba + sssd) exists; Entra ID, Okta, Google Workspace and FreeIPA are equally first-class targets, so nothing outside
`providers/<name>/` may assume AD. Enroll, decide who may sign in (and who gets
sudo), survive updates, leave. Other tools (MDMs, agents) build on it through the CLI and `status --json`; it is not a
platform and doesn't manage the device. It edits PAM, nsswitch, SDDM and sudoers, so mistakes lock people out.
Status: prototype; only the AD provider exists, verified in a VM against Samba AD. Public docs are the MkDocs site in `docs/`.

## Before you change anything
1. Read the hard rules below. Run `test/lab-check.sh` if the task needs the lab.
2. Skim `docs/dev/` (`architecture.md`, `testing.md`, `findings.md`) for the area you're touching. `findings.md` lists traps already hit.
3. Open work is GitHub issues: a queue for agents (see "Picking work" below). Pick or create an issue first.

## Hard rules
- **Never test PAM/sssd/nsswitch/SDDM changes on the host machine.** A bad PAM edit locks the owner out. Use the QEMU VM lab (`test/`).
- Never edit `/usr/share/omarchy/` (package-owned, overwritten by `omarchy update`). Use `/etc` drop-ins and markers.
- Enforcement lives in root-owned `/etc`.
- Default is deny. Local accounts must keep working when sssd or `pam_sss.so` is missing or broken (that's PAM correctness, not an undo feature).
- **Scope is authentication.** Enrollment, who may sign in, directory-provided authorization (sudo groups, offline lifetime, later GPO), keeping it working across updates, `leave`. No device posture/compliance, inventory, hardening, tamper resistance or undo machinery (timers, backups, rollback): that's the MDM's or the deployer's job. Test: would it belong in a plain Linux directory client? See `docs/dev/architecture.md#scope`.
- No AUR dependencies (the AD provider joins with samba `net ads join`; home dirs via `pam_mkhomedir`). A directory whose client is AUR-only needs an owner decision first.
- Don't `pkill -f` (it kills your own shell); find processes by PID. Don't commit `test/vm/images`, `test/vm/keys`, credentials or real hostnames.
- Don't publish, tag, force-push or change repo settings without the owner asking.

## Layout
    bin/monarchy-identity    core CLI (status|enroll|leave|policy|reassert|install-hooks|providers)
    providers/<name>/        one per directory (ad today): enroll matches unenroll policy reassert status detect pam.conf (+lib.sh)
    lib/                     common.sh, pamedit.py (idempotent BEGIN/END-marked PAM editor; the provider names the module)
    sddm-theme/              login theme: Omarchy's look + a username field (stock theme only logs in the last user)
    hooks/                   reassert.sh + post-update wrapper
    packaging/               PKGBUILD, alpm hook, install scriptlet, default config
    test/                    dc (Samba AD container for the ad provider), vm (Arch QEMU client, lib.sh + e2e suites), unit (+ stub-provider)
    docs/                    MkDocs site (user-facing docs + developer pages)
    .github/workflows/       ci.yml, release.yml, docs.yml

## Commands
Prerequisites for the lab: Docker, QEMU/KVM + OVMF, ssh, python3, node (polkit rule tests). Details: `docs/dev/testing.md`.

    test/lab-check.sh                 # prerequisites + lab state; prints the exact fix for anything missing
    test/unit/run.sh                                                                   # fast layer: real CLI, temp /etc, stub commands; seconds, no lab or root
    bash hooks/test-reassert.sh                                                        # no lab needed
    cd test/dc && docker compose up -d && ./seed-users.sh                              # directory
    (cd test/vm && ./fetch-image.sh && (setsid ./run.sh </dev/null >vm.log 2>&1 &))   # VM; makes its own ssh key; first boot ~1 min
    test/vm/deploy.sh [--fixtures]    # push repo to the VM (--fixtures resets PAM to stock Omarchy, removes the package)
    test/vm/e2e*.sh                   # one suite; each prints RESULT: ALL PASS
    test/run-all.sh                   # everything
    ssh -i test/vm/keys/id_oi -p 2222 tester@127.0.0.1                                 # the VM
Lab credentials are throwaway and loopback-only: Administrator/alice/bob/carol, password `Passw0rd!Test`.

## Definition of done
- Two test layers (`docs/dev/testing.md`). The fast layer (`test/unit/run.sh`) always passes and is where logic gets
  tested: validation, refusals, generated config, PAM/nsswitch/SDDM edits, `leave`, `status --json`. The lab
  (`test/vm/e2e*.sh`) is required when a change touches what only real sssd, PAM or a directory can show: enroll/join,
  sign-in through the PAM stack, offline cache, the package; add `e2e-greeter.sh` for login-screen changes.
  Suites must not depend on what ran before them: start from `fresh`, and cover a fresh vs an existing computer
  account explicitly rather than by re-running.
- `enroll` checks everything the directory can reject before it changes sign-in; `leave` removes every change enroll made.
- New PAM edit: goes through `lib/pamedit.py`, rule is `-`-prefixed, safe when the module is missing, has a remove/idempotency test.
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
- Provider contract (`docs/dev/writing-a-provider.md`): what's shared across directories lives in the core (shared options, PAM, SDDM, sudoers; a provider gets its own options and the resolved policy); `enroll` checks everything the directory can reject before registering, and the core edits PAM last; a re-run picks up after a failure (no rollback machinery). `unenroll` removes every change enroll made. State goes in `/etc/monarchy-identity/config.toml` (flat `key = "value"`). See `docs/dev/writing-a-provider.md`.
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
GitHub issues are the work queue for agents. Labels: `P0` (blocks real use) to `P3` (polish). Assume work needs the
lab unless the issue says otherwise. Take the highest-priority open issue without an assignee or open PR; each issue body says
what done looks like. Close it from the PR (`Fixes #N`). If you find new work, open an issue in the same shape rather
than expanding the current change.

## Workflow
Branch from `main`, open a PR, let CI run; releases are cut by tagging `vX.Y.Z` (see the `release` skill; the tag must match `pkgver`).
Security issues: private advisory (see `SECURITY.md`), not a public issue.
