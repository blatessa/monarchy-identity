# Testing

Never test PAM, sssd, nsswitch or SDDM changes on a real machine: a bad edit locks the owner out. Use the lab. For the AD provider it is a
throwaway Samba AD domain `CORP.TEST` in Docker (published on loopback only) and an Arch client VM under QEMU/KVM
(UEFI, user-mode networking, host address 10.0.2.2). The VM is stock Arch with Omarchy's PAM and SDDM files copied in
as fixtures; it is not a full Omarchy install.

Agents and contributors: the working rules and definition of done are in
[AGENTS.md](https://github.com/blatessa/monarchy-identity/blob/main/AGENTS.md).

## Tests that need no lab

```bash
bash test/unit/validation.sh      # input validation
bash test/unit/naming.sh          # computer names, OU conversion
bash hooks/test-reassert.sh       # reassert hook wrapper
bash shell-plugin/tests/run.sh    # widget manifest, Model.js (needs node), qmllint when installed
```

These also run in CI.

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

## Running the suites

```bash
test/run-all.sh          # every suite; each prints RESULT: ALL PASS
test/vm/e2e.sh           # or one suite
```

Each suite is built around as few enrollments as possible. Add a check to the suite that already has the enrollment
you need before writing a new one; a new suite pays for its own deploy, enroll and leave.

| Suite | Covers |
|---|---|
| `e2e` | The core: every Omarchy PAM service (allowed, refused, wrong password, local), home creation, `passwd`, repair with `reassert`, local users with sssd stopped and `pam_sss.so` missing, `leave` |
| `e2e-policy` | Implied modes, groups/assigned/any, `--sudo-groups`, `--offline-days`, autologin, `policy set` without re-joining, refused changes, systemd start limit, `--if-needed` |
| `e2e-enroll` | `--computer-name`, `--ou`, password file and variable, `--replace-computer-account`, re-running a half-finished enrollment, hooks and widget installers |
| `e2e-refused` | Everything `enroll` must refuse before sign-in changes (bad input, wrong password, unknown group, DC down, colliding or generic names, unsafe password files). Never enrolls. |
| `e2e-offline` | Expired password, cached sign-in with the DC down, recovery |
| `e2e-dns` | Enrolling without `--server` (DNS SRV discovery) |
| `e2e-package` | The real package: install, pacman hook repair, removal while enrolled |
| `e2e-greeter` | The real SDDM greeter (X11), driven with typed keys |

Suites share `test/vm/lib.sh`: `fresh` (deploy and reset), `enroll`/`leave`, `expect` (run a PAM service), `check`,
`cli`/`scli` (the CLI as tester/root) and `result`.

Suites don't depend on each other or on order: each starts with `fresh` (stock PAM, not enrolled, stale lab
computer accounts deleted). Behaviour that depends on leftover state, such as an existing computer account, gets an
explicit check (`e2e-enroll`, `e2e-refused`) instead of relying on a second run.

## Helpers

- `test/vm/trylogin.sh USER PW` and `test/vm/pamtest.py SERVICE USER PW` exercise the PAM stack (there is no
  `sshpass` or `pamtester` on Arch).
- `e2e-greeter.sh` uses `qmon.py` (QEMU monitor `sendkey` and `screendump`); the VM must have been started by the
  current `run.sh` (`-vga std` plus the monitor socket). `install-package.sh` builds and installs the real package.
- DNS lab: `test/dc/fix-dns.sh` points the DC's A record at 10.0.2.2; `e2e-dns.sh` configures the VM resolver.
- Render the login theme on a host without touching system configuration:
  `sddm-greeter-qt6 --test-mode --theme sddm-theme/monarchy-identity` and capture with `grim`.

## Writing tests

- Quote inputs that go through ssh with `q` (`printf %q`); use `grep -F` for computer names (`$` is a regex anchor).
- Reset faillock after enrollment, not before: before it, directory users do not resolve and the reset silently does
  nothing.
- A new PAM edit needs a remove and idempotency check.
- Print diagnostics on a failing step (`diag()` in `e2e-greeter.sh`).

## Continuous integration

`.github/workflows/ci.yml` runs on pushes to `main` and on pull requests (skipped for documentation-only changes; a
newer push cancels the run in progress):

- **Unit tests and lint**: shellcheck (errors only), Python syntax, the unit tests, the hook test, the widget test.
- **Build the Arch package**: `makepkg` in an `archlinux:base-devel` container and a check of the package contents.

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

Omarchy's real greeter (SDDM inside Hyprland), the Quickshell lock screen, Windows AD, every non-AD directory (no providers yet), a real
`omarchy update` run, and the widget in a live shell.

## Building these docs

```bash
python -m venv .venv && .venv/bin/pip install -r .github/docs-requirements.txt
.venv/bin/mkdocs serve            # live preview
.venv/bin/mkdocs build --strict   # what CI runs
```
