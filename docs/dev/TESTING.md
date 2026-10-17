# Testing

Never test PAM/sssd/nsswitch/SDDM changes on a real machine. Use the lab: a throwaway Samba AD (`CORP.TEST`, Docker,
loopback only) and an Arch client VM (QEMU/KVM, UEFI, user-mode net, host = 10.0.2.2). The VM is stock Arch with
Omarchy's PAM/SDDM files copied in as fixtures, not a full Omarchy install.

## CI
GitHub Actions (`.github/workflows/ci.yml`) runs the unit tests, shellcheck (errors), the hook and widget tests, and builds
the Arch package in a container. Docs-only changes skip CI, and a newer push cancels the run in flight.

## Releases
Bump `pkgver` in `packaging/PKGBUILD`, commit, then `git tag vX.Y.Z && git push --tags`. `release.yml` re-runs CI, checks
the tag matches `pkgver`, and publishes the `.pkg.tar.zst` files plus `SHA256SUMS` as a GitHub release with generated notes. The VM/Samba suites need KVM and Docker and are run locally (`test/run-all.sh`).

## Bring-up
    cd test/dc && docker compose up -d && ./seed-users.sh
    cd ../vm && ./fetch-image.sh                                   # once, checksum-verified
    (setsid ./run.sh </dev/null >vm.log 2>&1 &)                    # first boot: cloud-init, ~1 min
    test/vm/deploy.sh                                              # push the repo (--fixtures resets PAM to stock Omarchy)

VM: `ssh -i test/vm/keys/id_oi -p 2222 tester@127.0.0.1`. Stop it by PID (`pgrep -x qemu-system-x86`).
Lab credentials (throwaway): Administrator / alice / bob / carol, password `Passw0rd!Test`.
alice (allowed, in `oi-admins`), bob (allowed), carol (directory-only: must be denied).

## Running
    test/run-all.sh                    # every suite, ~12-16 min, each prints RESULT: ALL PASS
    test/vm/e2e*.sh                    # or one suite
    bash test/unit/*.sh                # no VM needed (input validation, check)
    bash hooks/test-reassert.sh; bash shell-plugin/tests/run.sh

Suites: e2e (enrol/drift/leave), account, policy, modes, services, dns, offline, package, safety, failure, resilience,
passwd, expired, sudo, noninteractive, greeter. Run e2e at least twice after touching enroll/unenroll: failures have
been order-dependent (fresh vs pre-existing computer account).

## Helpers
- `test/vm/trylogin.sh USER PW` (SSH_ASKPASS) and `pamtest.py SERVICE USER PW` (ctypes libpam): no sshpass/pamtester on Arch.
- `e2e-greeter.sh` drives the REAL SDDM greeter (X11) with `qmon.py` (QEMU monitor sendkey/screendump). Needs the VM
  started by the current `run.sh` (`-vga std` + monitor socket); `install-package.sh` builds and installs the real package.
- DNS lab: `test/dc/fix-dns.sh` points the DC's A record at 10.0.2.2; `e2e-dns.sh` sets the VM resolver.
- Render the theme on the host without touching system config: `sddm-greeter-qt6 --test-mode --theme DIR` + `grim`.
- Always print diagnostics on a failing e2e step (`diag()` in e2e-greeter.sh).

## Writing tests
- Inputs that go through ssh must be `printf %q`-quoted. Use `grep -F` for computer names (`$` is a regex anchor).
- Reset faillock AFTER enrol (before it, directory users don't resolve and the reset is a silent no-op).
- Any new PAM edit needs a remove/idempotency check.

## Not yet verified
Omarchy's real greeter (SDDM inside Hyprland), the Quickshell lock screen, Windows AD, FreeIPA, Entra/OIDC, a real
`omarchy update` run, and the widget in a live shell. Don't first-test on a daily driver.
