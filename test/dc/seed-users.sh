#!/bin/bash
# Create test users and groups in the running DC. Idempotent-ish.
set -euo pipefail
sc() { docker exec oi-test-dc samba-tool "$@"; }
sc group add oi-laptop-users 2>/dev/null || true
sc group add oi-admins 2>/dev/null || true
for u in alice bob carol; do
  sc user create "$u" 'Passw0rd!Test' 2>/dev/null || true
done
# one member per call: samba-tool rejects the WHOLE call if any listed user is already a member
for u in alice bob; do sc group addmembers oi-laptop-users "$u" 2>/dev/null || true; done
sc group addmembers oi-admins alice 2>/dev/null || true
# fail loudly if the lab is not in the expected state (tests depend on it)
members=$(sc group listmembers oi-laptop-users | sort | tr '\n' ' ')
[[ $members == "alice bob " ]] || { echo "lab group oi-laptop-users has unexpected members: $members" >&2; exit 1; }
# carol exists in the directory but is in no allowed group: must be DENIED by login.mode=groups
echo "users: alice(allowed,admin) bob(allowed) carol(directory-only, must be denied)"
