# Self-healing

Omarchy updates, migrations and manual edits can rewrite the files that monarchy-identity manages. Three mechanisms
re-apply them.

| Mechanism | Runs as | Trigger | Notes |
|---|---|---|---|
| `monarchy-identity-reassert.path` | root (systemd) | A change to `/etc/pam.d/system-auth`, `/etc/pam.d/omarchy-lock-password`, `/etc/nsswitch.conf`, `/etc/sddm.conf.d` or `/etc/sudoers.d` | Runs `monarchy-identity reassert` within seconds. Enabled by `enroll`, disabled first by `leave`. This is the mechanism to rely on. |
| pacman hook (`monarchy-identity.hook`) | root | A transaction that installs or upgrades `pambase`, `sssd`, `filesystem`, `omarchy` or `omarchy-settings` | Runs `hooks/reassert.sh` after the transaction. |
| Omarchy post-update hook | the desktop user | `omarchy update` | Optional: `monarchy-identity install-hooks`. Runs with `sudo -n`. A user can delete it, so it is a convenience, not a control. |

`reassert` is idempotent. It re-applies the nsswitch and PAM edits, the autologin override, the sudoers drop-in and
the login theme according to the saved configuration, and restarts sssd if it is not running. It fails if
`/etc/sssd/sssd.conf` is missing, which means the machine needs re-enrolment.

State-changing commands (`enroll`, `leave`, `reassert`, `confirm`, `policy set`) take a lock at
`/run/monarchy-identity.lock`, so the path unit cannot re-add edits while `leave` is removing them.

`status --json` reports drift: `details.pam_*` or `details.nss_sss` equal to `"false"` while `enrolled` is true.
`self_heal` shows whether the path unit is active. See [Posture report](../reference/posture.md).

A plain pacman upgrade of a package that owns a modified file writes a `.pacnew` and keeps the edited file, so drift
normally comes from Omarchy migrations or manual edits.
