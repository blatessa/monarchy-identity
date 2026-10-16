#!/bin/bash
# Create test users and groups in the running DC. Idempotent-ish.
set -euo pipefail
sc() { docker exec oi-test-dc samba-tool "$@"; }
sc group add oi-laptop-users 2>/dev/null || true
sc group add oi-admins 2>/dev/null || true
for u in alice bob carol; do
  sc user create "$u" 'Passw0rd!Test' 2>/dev/null || true
done
sc group addmembers oi-laptop-users alice,bob 2>/dev/null || true
sc group addmembers oi-admins alice 2>/dev/null || true
# carol exists in the directory but is in no allowed group: must be DENIED by login.mode=groups
echo "users: alice(allowed,admin) bob(allowed) carol(directory-only, must be denied)"
