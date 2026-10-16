#!/bin/bash
# Validates the plugin without a running shell. Exit non-zero on failure.
set -euo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

echo "== manifest.json"
python3 -I - "$D/manifest.json" <<'PY' || fail=1
import json, sys
m = json.load(open(sys.argv[1]))
# Fields the existing netmojo.omdrop / omarchy.tailscale bar-widget manifests use.
need = ["schemaVersion", "id", "name", "version", "author", "license", "description", "kinds", "entryPoints", "barWidget"]
miss = [k for k in need if k not in m]
assert not miss, f"missing top-level: {miss}"
assert m["schemaVersion"] == 1
assert m["kinds"] == ["bar-widget"], m["kinds"]
assert m["entryPoints"].get("barWidget") == "Panel.qml"
bw = m["barWidget"]
for k in ["displayName", "description", "category", "allowMultiple", "defaultSection", "defaults", "schema"]:
    assert k in bw, f"barWidget missing {k}"
keys = {s["key"] for s in bw["schema"]}
assert set(bw["defaults"]) <= keys, "defaults without schema entry"
for s in bw["schema"]:
    for k in ["key", "type", "label", "defaultValue"]:
        assert k in s, f"schema entry missing {k}"
import os
assert os.path.exists(os.path.join(os.path.dirname(sys.argv[1]), m["entryPoints"]["barWidget"]))
print("ok")
PY

echo "== Model.js (node)"
if command -v node >/dev/null; then node "$D/tests/test_model.js" || fail=1; else echo "skipped: node not found"; fi

echo "== qmllint"
Q=$(command -v qmllint || command -v qmllint6 || ls /usr/lib/qt6/bin/qmllint 2>/dev/null || true)
if [[ -n $Q ]]; then
  # qs.* modules only exist inside the running shell, so import warnings are expected;
  # fail only on real syntax errors.
  out=$("$Q" "$D/Panel.qml" 2>&1 || true)
  if grep -qiE 'syntax error|Expected|Unexpected' <<<"$out"; then echo "$out"; fail=1; else echo "ok (no syntax errors; import warnings ignored)"; fi
else
  echo "skipped: qmllint not found (install qt6-declarative)"
fi
exit $fail
