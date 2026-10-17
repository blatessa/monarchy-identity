---
name: pam-change
description: Checklist for any change that edits PAM stacks, nsswitch, SDDM config, sssd config or sudoers. Use before and after touching lib/pamedit.py, providers/ad/*, packaging hooks, or the sddm theme/conf drop-ins.
---

# Changing what we write into system config

A mistake here locks users (including root, over SSH) out of a machine. The host is the owner's daily laptop: **test only in the VM** (`lab-e2e` skill).

## Rules every edit must satisfy
1. Goes through `lib/pamedit.py` (BEGIN/END `monarchy-identity` markers, skip counts computed from the real file). Other files: use `/etc` drop-ins with unique names; never edit `/usr/share/omarchy`.
2. Every PAM rule is `-`-prefixed and safe when `pam_sss.so` is missing or sssd is down. Account rules map `user_unknown`, `authinfo_unavail`, `module_unknown` to `ignore`. Local users and root must be unaffected. Read the header of `lib/pamedit.py`: a plain `default=bad` once failed EVERY login.
3. Idempotent (`apply` twice = once) and exactly reversible (`remove` restores byte-identical). Add the check.
4. `reassert` re-applies it (the pacman hook runs that after updates), `status` reports when it's missing, and `leave` removes it.
5. Both Omarchy services that matter are covered: `/etc/pam.d/system-auth` (everything funnels into it) and `/etc/pam.d/omarchy-lock-password` (lock screen). `su` uses pam_unix directly; there's no `polkit-1` service.
6. sssd restarts only via `sssd_restart`; `sssctl` always with `</dev/null` and `timeout`.
7. New file under `lib/`, `providers/`, etc. that the CLI sources: add it to `packaging/PKGBUILD` (`test/vm/e2e-package.sh` catches misses).

## Verify
- `test/unit/*.sh`, then in the VM: `e2e.sh` (every service, module missing / sssd down must not lock out locals), `e2e-refused.sh`, `e2e-package.sh`; add `e2e-greeter.sh` for theme/SDDM changes.
- Update `docs/dev/architecture.md` (files we write) and the user docs only if people see a difference; add a line to `docs/dev/findings.md` if you learned something non-obvious.
