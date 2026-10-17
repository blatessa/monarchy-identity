---
name: lab-e2e
description: Bring up the Samba AD + Arch VM lab, deploy the repo into it, run and diagnose e2e suites. Use before claiming any enroll/unenroll/PAM/sssd/SDDM change works, or when a test/vm/e2e*.sh suite fails.
---

# Running the lab

The lab is the slow layer. Logic (validation, refusals, generated config, PAM/nsswitch/SDDM edits, `status --json`) is
tested first in `test/unit/` against a temp `/etc` with stub commands (`test/unit/run.sh`, seconds, no lab). Reach for
the lab when a change needs real sssd, PAM or a directory, or before claiming a PAM/sssd/SDDM change works. If a lab
failure is really logic, reproduce it in `test/unit/` first.

Never run these steps against the host's `/etc`. Everything below targets the QEMU VM.

1. `test/lab-check.sh`. It lists what's missing with the exact fix. Ready = exit 0.
2. Directory: `cd test/dc && docker compose up -d && ./seed-users.sh`.
3. VM (background it, never `pkill -f`): `cd test/vm && ./fetch-image.sh` once, then
   `(setsid ./run.sh </dev/null >vm.log 2>&1 &)`. First boot ~1 min (cloud-init). It makes `keys/id_oi` itself.
4. Push code: `test/vm/deploy.sh`. Add `--fixtures` to reset PAM/SDDM to stock Omarchy, uninstall the package and delete stale computer accounts. Suites call it themselves when they need to.
5. Run one suite: `test/vm/e2e.sh` (core: every sign-in service, passwords, repair, policies and sudo, sssd down, leave, directory refusals and enroll options), or others (`ls test/vm/e2e*.sh`). Each ends with `RESULT: ALL PASS`. Default run: `test/run-all.sh` (fast layer plus the lab suites except the greeter). `test/vm/e2e-greeter.sh` is its own run, for login-screen changes.
6. Suites are independent (each starts with `fresh`). If a failure only shows up after another suite, that's leftover state: fix the reset or add an explicit check, don't re-run until it passes.

VM access: `ssh -i test/vm/keys/id_oi -p 2222 tester@127.0.0.1`. Lab credentials (throwaway, loopback): Administrator/alice/bob/carol, password `Passw0rd!Test`. alice and bob are allowed, carol is directory-only and must be denied.

## When a suite fails
- Print diagnostics first (journal, `monarchy-identity status`, `sssctl user-checks`, `/var/log/sssd/*.log` in the VM) before theorising. Read `docs/dev/findings.md` for the known traps.
- Shared state between suites: faillock (reset it AFTER enroll), stale computer account `OI-CLIENT$` (`deploy.sh --fixtures` deletes it; or `docker exec oi-test-dc samba-tool computer delete 'OI-CLIENT$'`), a stale sssd in `start-limit-hit` (`systemctl reset-failed sssd`).
- A hung `sssctl` or CLI holds `/run/monarchy-identity.lock`: find the process by PID with `ps`; don't `pkill -f`.
- VM bricked (everyone locked out): stop it by PID (`pgrep -x qemu-system-x86`), delete `test/vm/images/client.qcow2` and `OVMF_VARS.fd`, rerun `run.sh`.
- Stale cloud-init seed server on :8000 makes the VM boot with defaults; `run.sh` replaces any listener there.

## Writing a test
Logic goes in `test/unit/` (source `test/unit/lib.sh`: `sandbox`, `enroll`, `oi`, `refused`, `called`; stubs in `test/unit/stubs/`). Lab suites: source `test/vm/lib.sh` (`fresh`, `enroll`, `expect`, `check`, `scli`, `result`). Each suite pays for its own deploy/enroll/leave, so add checks to the suite that already has the right enrollment rather than starting a new one. Quote ssh inputs with `q`/`printf %q`; `grep -F` for computer names; any new PAM edit needs a remove/idempotency check. A new suite goes in `test/run-all.sh`.
