# Staying correct

Omarchy updates, its migrations and occasionally people edit the files that sign-in depends on. If one of those files
is overwritten, directory sign-in could silently stop working. monarchy-identity watches for this and puts its changes
back, so you don't have to.

## What repairs it

| What | When | Notes |
|---|---|---|
| **A watcher** (a root-owned system service) | Within seconds of a change to the sign-in, login-screen or sudo configuration | Enabled by `enroll`. This is the one to rely on; a user can't switch it off. |
| **A package-manager hook** | After pacman updates a package that can touch those files | Runs automatically. |
| **An `omarchy update` hook** (optional) | After `omarchy update` | `monarchy-identity install-hooks`, run as the desktop user. A user can delete it, so it's a convenience. |

All of them run the same idempotent repair (`monarchy-identity reassert`), which restores the edits from the saved
configuration and restarts the sign-in service if it stopped. Running it by hand is always safe.

## Seeing it

`monarchy-identity status` and `status --json` show whether the watcher is active and whether any managed file has
drifted ([Posture report](../reference/posture.md)). A compliance policy can require the watcher
(`require_self_heal`, see [Compliance checks](../guides/compliance-checks.md)).

## If it can't repair

If the saved configuration itself is gone, repair reports that the laptop needs to be enrolled again. Leaving the
directory (`leave`) turns the watcher off first, so it never fights an intentional removal.

Which files, services and hooks are involved is listed in [Files, units and variables](../reference/files.md).
