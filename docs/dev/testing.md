# Testing

Never test PAM, sssd, nsswitch or SDDM changes on a real machine: a bad edit locks the owner out. Use the lab. For the AD provider it is a
throwaway Samba AD domain `CORP.TEST` in Docker (published on loopback only) and an Arch client VM under QEMU/KVM
(UEFI, user-mode networking, host address 10.0.2.2). The VM is stock Arch with Omarchy's PAM and SDDM files copied in
as fixtures; it is not a full Omarchy install.

Agents and contributors: the working rules and definition of done are in
[AGENTS.md](https://github.com/blatessa/monarchy-identity/blob/main/AGENTS.md).

## Two layers

| Layer | Runs | Needs | Covers |
|---|---|---|---|
| Fast (`test/unit/`) | seconds, every PR in CI | bash, python3, `unshare -r` | Logic: input validation, refusals, generated `sssd.conf`/sudoers, policy changes, enroll options, PAM/nsswitch/SDDM edits, `leave`, `status --json` |
| Lab (`test/vm/`) | minutes, locally | the VM and the DC | What only real sssd, PAM and a directory can show: the join, sign-in through the PAM stack, offline cache, the package |

Put a check in the fast layer unless it needs real sssd, PAM or a directory. The fast layer is always required; the lab
is required when a change touches enroll/join, the PAM stack's behaviour, sssd, the package, or (`e2e-greeter`) the login
screen.

## The fast layer

```bash
test/unit/run.sh                  # all of it
bash test/unit/pam.sh             # or one suite
bash hooks/test-reassert.sh       # reassert hook wrapper
```

`test/unit/lib.sh` builds a sandbox per suite: a temp `/etc` seeded with the lab's Omarchy PAM and SDDM fixtures
(`test/vm/fixtures`), the real `bin/monarchy-identity` run as fake root (`unshare -r`), and stub commands
(`test/unit/stubs/`: `net`, `systemctl`, `getent`, `sssctl`, `visudo`, `kinit`, `uname`, `omarchy`, ...) first on `PATH`.
Paths come from the `MONARCHY_IDENTITY_*` overrides. Knobs are `STUB_*` variables (`STUB_GROUPS`,
`STUB_COMPUTERS`, `STUB_HOSTNAME`, `STUB_DC_DOWN`, `STUB_VISUDO_FAIL`, ...); `called` greps what the stubs saw.

| Suite | Covers |
|---|---|
| `refused` | Everything `enroll` must refuse before sign-in changes: bad input, wrong password, unknown group, DC down, colliding or generic names, unsafe password files. Each refusal leaves the temp `/etc` unchanged. |
| `policy` | Implied modes, `policy set` changing only what's passed, refusals, `--if-needed`, generated `sssd.conf` and sudoers, autologin |
| `enroll` | `--computer-name`, `--ou`, password sources, `--replace-computer-account`, re-running a half-finished enrollment, login theme, hook installer |
| `pam` | PAM/nsswitch/SDDM edits on Omarchy's real files: apply, remove, idempotent, skip counts, another provider's module, unsafe module arguments refused; `leave` removes only marked files; autologin merge order |
| `provider` | The provider contract, against `test/unit/stub-provider` installed next to `ad`: the core validates shared options, the provider gets only its own plus the resolved policy, its PAM module is inserted, `policy`, `--if-needed`, `status`, `reassert`, `leave` |
| `status` | `status --json` shape and that its checks follow reality |
| `validation`, `naming` | Input validators, computer names and OU conversion |

A stub that mirrors real tool output cites where it was observed in `findings.md`. When a lab run shows a stub
was wrong, fix the stub and the note. These also run in CI.

## The lab

Prerequisites: Docker, QEMU/KVM with OVMF (`edk2-ovmf`), ssh, python3, curl and node. Check them and the lab state
with:

```bash
test/lab-check.sh
```

It prints the exact command to fix each missing item and exits 0 when the lab is ready.

Bring-up:

```bash
cd test/dc && docker compose up -d && ./seed-users.sh                 # directory
cd ../vm && ./fetch-image.sh                                           # once, checksum-verified
(setsid ./run.sh </dev/null >vm.log 2>&1 &)                            # first boot runs cloud-init, about 1 minute
test/vm/deploy.sh --fixtures                                           # push the repo, reset PAM to stock Omarchy
```

`run.sh` generates the VM's ssh key (`test/vm/keys/id_oi`) on first use and renders the cloud-init seed from
`test/vm/seed/user-data.tmpl`. Keys and images are never committed. Connect with:

```bash
ssh -i test/vm/keys/id_oi -p 2222 tester@127.0.0.1
```

`deploy.sh` without `--fixtures` keeps the current PAM files. `--fixtures` resets `/etc/pam.d` and `sddm.conf.d` to
the Omarchy fixtures, removes the installed package, and deletes stale lab computer accounts. Stop the VM by PID
(`pgrep -x qemu-system-x86`).

Lab credentials are throwaway: `Administrator`, `alice`, `bob`, `carol`, password `Passw0rd!Test`. `alice` is
allowed and in `oi-admins`, `bob` is allowed, `carol` exists in the directory only and must be refused.

## Labs for other directories

Each new provider brings its own lab directory: a container where one exists (FreeIPA), otherwise a test tenant or
a documented stand-in, chosen in the provider's issue. The client VM, `lib.sh` and the core suites are shared.

**Entra ID** has no container: `test/vm/e2e-entra.sh` runs against a real test tenant and is skipped (passing) without
one. It needs:

- the himmelblau package in the VM (build `pkgbuilds/himmelblau` from `omacom/omarchy-pkgs`, `pacman -U` it), until
  it's in Omarchy's repository;
- in the tenant: users `alice`, `bob`, `carol` with password-only sign-in, groups `linux-users` (alice, bob) and
  `linux-admins` (alice), and an app registration with the `Group.Read.All` and `User.Read.All` application
  permissions (admin consent) and a client secret;
- an env file outside the repo, named by `ENTRA_LAB_ENV`, with `ENTRA_TENANT`, `ENTRA_CLIENT_ID`,
  `ENTRA_CLIENT_SECRET`, and `ENTRA_ALICE`/`ENTRA_ALICE_PASSWORD` (same for `BOB`, `CAROL`; full sign-in names);
- `az` signed in to the tenant, so the suite can delete the device each run registers (otherwise delete `oi-client`
  under Devices yourself).

`test/lab-check.sh` checks these when `ENTRA_LAB_ENV` is set, as notes: the suite is opt-in, so a missing tenant
doesn't make the lab "not ready".

Never loop a wrong password against the tenant: `pam_himmelblau` re-prompts instead of failing, and Entra throttles
the account. `pamtest.py` gives up when the same prompt comes a third time.

## Running the lab suites

```bash
test/run-all.sh          # the fast layer plus the default lab suites
test/vm/e2e.sh           # or one suite
test/vm/e2e-greeter.sh   # login-screen changes only; not part of the default run
```

Each suite is built around as few enrollments as possible. Add a check to the suite that already has the enrollment
you need before writing a new one; a new suite pays for its own deploy, enroll and leave.

| Suite | Covers |
|---|---|
| `e2e` | The core: the directory's refusals (wrong password, unknown group), every Omarchy PAM service (allowed, refused, wrong password, local), a real admin prompt, home creation, `passwd`, repair with `reassert`, who-may-sign-in policies and sudo as sssd enforces them, the sudoers and polkit drop-ins (`visudo -c`, the theme rule granted only to allowed users), local users with sssd stopped and `pam_sss.so` missing, `leave`; then `--computer-name`, `--ou`, `--password-file`, an existing computer account (refused, then `--replace-computer-account`) re-running a half-finished enrollment, and `enroll --if-needed` on an enrolled laptop (converges, doesn't re-join) |
| `e2e-offline` | Enroll refused with the DC down, an expired password through SDDM's PAM stack (let through and marked, wrong password counted once, not-allowed refused, the guard while SDDM predates enroll), cached sign-in with the DC down, `--offline-days` expiry (the VM's clock moved forward), recovery |
| `e2e-dns` | Enrolling without `--server` (DNS SRV discovery) |
| `e2e-package` | The real package: install, pacman hook repair (also on its own upgrade), removal while enrolled (PAM, nsswitch, SDDM, sudoers and polkit drop-ins gone) |
| `e2e-greeter` | The real SDDM greeter (X11), driven with typed keys: sign-in, refusals, local user; an expired password in the change-password screen (Hyprland session): giving up, then changing it and reaching the desktop. Separate run: only for login-screen changes |

Suites share `test/vm/lib.sh`: `fresh` (deploy and reset), `enroll`/`leave`, `expect` (run a PAM service), `check`,
`cli`/`scli` (the CLI as tester/root) and `result`.

Suites don't depend on each other or on order: each starts with `fresh` (stock PAM, not enrolled, stale lab
computer accounts deleted). Behaviour that depends on leftover state, such as an existing computer account, gets an
explicit check (`e2e`, `unit/refused`) instead of relying on a second run.

## Helpers

- `test/vm/trylogin.sh USER PW` and `test/vm/pamtest.py SERVICE USER PW` exercise the PAM stack (there is no
  `sshpass` or `pamtester` on Arch).
- `test/vm/adminprompt.py IDENTITY PW` answers a real polkit admin prompt (`pkexec` under `pkttyagent`, through
  polkit's sandboxed helper); `admin_prompt` in `lib.sh`. The VM needs polkit (`lab-check.sh` says how).
- `e2e-greeter.sh` uses `qmon.py` (QEMU monitor `sendkey` and `screendump`); the VM must have been started by the
  current `run.sh` (`-vga std` plus the monitor socket). `install-package.sh` builds and installs the real package.
- DNS lab: `test/dc/fix-dns.sh` points the DC's A record at 10.0.2.2; `e2e-dns.sh` configures the VM resolver.
- Render the login theme on a host without touching system configuration:
  `sddm-greeter-qt6 --test-mode --theme sddm-theme/monarchy-identity` and capture with `grim`.

## Writing tests

- Quote inputs that go through ssh with `q` (`printf %q`); use `grep -F` for computer names (`$` is a regex anchor).
- Reset faillock after enrollment, not before: before it, directory users do not resolve and the reset silently does
  nothing.
- A new PAM edit needs a remove and idempotency check (`test/unit/pam.sh`).
- Logic goes in `test/unit/`; a lab suite is for what stubs cannot show.
- Print diagnostics on a failing step (`diag()` in `e2e-greeter.sh`).

## Continuous integration

`.github/workflows/ci.yml` runs on pushes to `main` and on pull requests (skipped for documentation-only changes; a
newer push cancels the run in progress):

- **Unit tests and lint**: shellcheck (errors only), Python syntax, the fast layer (`test/unit/run.sh`), the hook test.
- **Build the Arch package**: `packaging/build-local.sh` (makepkg on the checkout) in an `archlinux:base-devel`
  container and a check of the package contents.

The lab suites need KVM and Docker and run locally.
`.github/workflows/docs.yml` builds this site with `mkdocs build --strict` on pull requests and deploys it to GitHub
Pages from `main`.

## Releases

Set `pkgver` in `packaging/PKGBUILD`, commit, then tag and push:

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
```

`.github/workflows/release.yml` re-runs CI, checks that the tag matches `pkgver`, and publishes the
`.pkg.tar.zst` files and `SHA256SUMS` as a GitHub release with generated notes.

## Not yet verified

The lab suites against a Windows DC (Windows Server 2025 was only tried by hand, on a real Omarchy laptop: greeter, lock screen,
console, `omarchy update`), and every non-AD directory (no providers yet).

## Building these docs

```bash
python -m venv .venv && .venv/bin/pip install -r .github/docs-requirements.txt
.venv/bin/mkdocs serve            # live preview
.venv/bin/mkdocs build --strict   # what CI runs
```
