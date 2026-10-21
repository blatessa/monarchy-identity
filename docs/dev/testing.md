# Testing

Don't test PAM, sssd, nsswitch or SDDM changes on a real machine: a bad edit locks you out. Use the lab: a Samba AD
domain `CORP.TEST` in Docker (loopback only) and an Arch VM under QEMU/KVM (UEFI, user networking, host 10.0.2.2) with
Omarchy's PAM and SDDM files as fixtures (not a full Omarchy install).

| Layer | Time | Needs | Covers |
|---|---|---|---|
| Fast, `test/unit/` | ~2 s, every PR in CI | bash, python3, `unshare -r` | Validation, refusals, generated config, PAM/nsswitch/SDDM edits, `leave`, `status --json`, `lib/login-steps` |
| Lab, `test/vm/` | minutes, local | VM, DC, a tenant for Entra | Real join, sign-in through PAM, offline cache, the package, the greeter |

Logic goes in the fast layer. The lab is required for enroll/join, PAM stack behaviour, sssd/himmelblau, the package,
and (`e2e-greeter`) the login screen.

## Fast layer

```bash
test/unit/run.sh          # all suites, in parallel
bash test/unit/pam.sh     # one
```

`test/unit/lib.sh` gives each suite a temp `/etc` seeded from `test/vm/fixtures`, the real CLI as fake root
(`unshare -r`), and stub commands (`test/unit/stubs/`) first on `PATH`. Paths come from `MONARCHY_IDENTITY_*`
overrides, stub knobs are `STUB_*` variables, `called` greps what the stubs saw. A stub copies real output and cites
where it was captured in `findings.md`.

| Suite | Covers |
|---|---|
| `refused` | What `enroll` refuses before changing anything; each refusal leaves `/etc` unchanged |
| `policy` | Modes, `policy set`, `--if-needed`, generated `sssd.conf` and sudoers, autologin |
| `enroll` | `--computer-name`, `--ou`, password sources, `--replace-computer-account`, re-runs, theme, hooks |
| `pam` | PAM/nsswitch/SDDM edits on Omarchy's files: apply, remove, idempotency, skip counts |
| `provider` | The provider contract against `test/unit/stub-provider` |
| `entra` | The Entra provider with a stub Graph and `aad-tool` |
| `greeter` | `lib/password-expired`, `lib/login-steps` against scripted pam_himmelblau conversations, `lib/sddm-session` |
| `status`, `validation`, `naming`, `reassert`, `config` | As named |

## Lab

```bash
test/lab-check.sh                                                      # what's missing, with the fix
cd test/dc && docker compose up -d && ./seed-users.sh                  # directory
cd ../vm && ./fetch-image.sh && (setsid ./run.sh </dev/null >vm.log 2>&1 &)   # first boot ~1 min
test/vm/deploy.sh [--fixtures]                                         # push the CLI (~1 s); --fixtures resets PAM/SDDM, removes the package
ssh -i test/vm/keys/id_oi -p 2222 tester@127.0.0.1
```

- `run.sh` makes the ssh key and renders the cloud-init seed. Keys and images are never committed.
- Suites share one ssh connection (`test/vm/ssh.sh`, open 2 minutes after the last call). So test sign-in with `pt`
  (`pamtest.py`) or `trylogin.sh`, not by whether ssh connects.
- Stop the VM by PID (`pgrep -x qemu-system-x86`).
- Credentials (throwaway): `Administrator`, `alice` (allowed, `oi-admins`), `bob` (allowed), `carol` (directory only,
  refused), password `Passw0rd!Test`.

### Entra ID

`e2e-entra.sh`, and the Entra parts of `e2e-package.sh` and `e2e-greeter.sh`, need a test tenant and skip (passing)
without one:

- The himmelblau package in `test/vm/images/`: `test/vm/himmelblau/build.sh` builds the omarchy-pkgs recipe
  (#1274, stock himmelblau 4.0.6) in an Arch container (~2 minutes, skipped when `images/` has that version).
  Suites install it in the VM. The lab tests what people install: no patched builds.
- In the tenant: `alice`, `bob`, `carol` with password-only sign-in; groups `linux-users` (alice, bob) and
  `linux-admins` (alice); an app registration with `Group.Read.All` and `User.Read.All` application permissions
  (admin consent) and a client secret.
- An env file outside the repo, named by `ENTRA_LAB_ENV`: `ENTRA_TENANT`, `ENTRA_CLIENT_ID`, `ENTRA_CLIENT_SECRET`,
  `ENTRA_ALICE`/`ENTRA_ALICE_PASSWORD` (same for `BOB`, `CAROL`; full sign-in names).
- Optional, for the code checks: `dave` in `linux-users` with per-user MFA and a third-party authenticator app
  ("I want to use a different authenticator app", "Can't scan image?"), and `ENTRA_DAVE`, `ENTRA_DAVE_PASSWORD`,
  `ENTRA_DAVE_TOTP_SECRET` (that key). Re-registering dave's authenticator changes the key: update the env file.
  The suite says so when Entra answers `OathCodeIncorrect`.
- Optional: `az` signed in to the tenant (devices administrator), so the suites delete the device each run registers
  (otherwise delete `oi-client` under Devices by hand).

Don't loop a wrong password or code against the tenant: pam_himmelblau re-prompts instead of failing and Entra
throttles the account. `pamtest.py` gives up on the third identical prompt. Each run sends one wrong password (bob) and
one wrong code (dave).

## Suites

```bash
test/run-all.sh            # fast layer + default lab suites
test/vm/e2e.sh             # one suite
test/vm/e2e-greeter.sh     # login screen; not in the default run
```

| Suite | Covers |
|---|---|
| `e2e` | AD core: refusals, every Omarchy PAM service, admin prompt, homes, `passwd`, `reassert`, policies and sudo, sssd down / module missing, `leave`, enroll options, existing computer account, `--if-needed` |
| `e2e-offline` | Enroll with the DC down, expired password through SDDM's stack, cached sign-in, `--offline-days` expiry (VM clock moved), recovery |
| `e2e-dns` | Enroll without `--server` (DNS SRV) |
| `e2e-entra` | Refused enrolls, enroll, every PAM service, groups and sudo, password-only `ssh` refused, the login screen asking once and saying why, MFA code (optional user), offline, enroll again, `leave`, enroll after `leave` (~2 minutes) |
| `e2e-package` | Install, pacman hook repair, removal while enrolled; the same for Entra with a tenant |
| `e2e-greeter` | The real SDDM greeter driven by keystrokes: sign-in, refusals, the expired-password screen; with a tenant, a wrong Entra password tried once and the MFA code line |

Each suite starts with `fresh` (deploy, stock PAM, not enrolled) and doesn't depend on the others. Add checks to the
suite that already has the enrollment you need. `lib.sh`: `fresh`, `enroll`/`leave`, `expect`, `pt`, `check`,
`cli`/`scli`, `hb_mark`/`hb_log`/`steps` (himmelblaud's log by journal cursor), `result`.

## Helpers

- `trylogin.sh USER PW`, `pamtest.py SERVICE USER PW [--messages]`: run a PAM stack (Arch has no `pamtester`).
- `adminprompt.py IDENTITY PW`: answer a real polkit prompt (`admin_prompt` in `lib.sh`).
- `qmon.py`: QEMU monitor `sendkey`/`screendump` for `e2e-greeter.sh`.
- `install-package.sh`: build and install the real package.
- `test/dc/fix-dns.sh`: point the DC's A record at 10.0.2.2 for `e2e-dns.sh`.
- Theme preview without touching the system: `sddm-greeter-qt6 --test-mode --theme sddm-theme/monarchy-identity`.

## Writing tests

Quote ssh inputs with `q`; `grep -F` for computer names; reset faillock after enrolling (before, directory users don't
resolve); a new PAM edit needs remove and idempotency checks; print diagnostics on failure.

## CI

`.github/workflows/ci.yml` on pushes to `main` and PRs (not docs-only): shellcheck (errors), Python syntax, the fast
layer, and an Arch package build with a contents check. `docs.yml` builds the site with `mkdocs build --strict` and
deploys it from `main`. The lab runs locally.

## Releases

Set `pkgver` in `packaging/PKGBUILD`, commit, `git tag vX.Y.Z && git push origin vX.Y.Z`. `release.yml` checks the
tag against `pkgver` and publishes the packages and `SHA256SUMS`.

## Docs

```bash
python -m venv .venv && .venv/bin/pip install -r .github/docs-requirements.txt
.venv/bin/mkdocs serve            # preview
.venv/bin/mkdocs build --strict   # what CI runs
```
