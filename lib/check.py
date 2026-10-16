#!/usr/bin/env python3
"""Evaluate `omarchy-identity status --json` (stdin) against a policy file.

usage: check.py POLICY_FILE [--json]        exit 0 = compliant, 1 = violations, 2 = bad policy/input

Policy: flat `key = "value"` lines (same format as config.toml); unknown keys are an error (typos must not
silently weaken a policy). Rules (all optional; only listed rules are checked):
  require_enrolled            = true
  require_self_heal           = true
  require_disk_encryption     = true
  require_firewall            = true
  require_secure_boot         = true
  require_tpm2                = true
  forbid_autologin            = true
  allowed_wheel_members       = root,admin     # anyone else in wheel fails
  max_screen_lock_seconds     = 600            # unknown fails: the rule asks for proof
  required_login_mode         = groups         # or assigned / any
  unknown_is_failure          = true           # default true; false => "unknown" values are skipped, not failed
"""
import json, re, sys

BOOL = {"require_enrolled", "require_self_heal", "require_disk_encryption", "require_firewall",
        "require_secure_boot", "require_tpm2", "forbid_autologin", "unknown_is_failure"}
OTHER = {"allowed_wheel_members", "max_screen_lock_seconds", "required_login_mode"}


def load_policy(path):
    pol = {}
    with open(path) as f:
        for n, line in enumerate(f, 1):
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            m = re.fullmatch(r'([a-z0-9_]+)\s*=\s*"?([^"]*)"?', line)
            if not m:
                raise ValueError(f"{path}:{n}: cannot parse '{line}'")
            k, v = m.group(1), m.group(2).strip()
            if k not in BOOL | OTHER:
                raise ValueError(f"{path}:{n}: unknown policy key '{k}'")
            if k in BOOL and v not in ("true", "false"):
                raise ValueError(f"{path}:{n}: {k} must be true or false")
            if k == "max_screen_lock_seconds" and not v.isdigit():
                raise ValueError(f"{path}:{n}: {k} must be a whole number of seconds")
            if k == "required_login_mode" and v not in ("groups", "assigned", "any"):
                raise ValueError(f"{path}:{n}: {k} must be groups|assigned|any")
            pol[k] = v
    return pol


def evaluate(pol, st):
    c = st.get("compliance", {})
    unk_fail = pol.get("unknown_is_failure", "true") == "true"
    out = []

    def rule(name, ok, detail):
        out.append({"rule": name, "result": "PASS" if ok is True else ("SKIP" if ok is None else "FAIL"), "detail": detail})

    def tri(name, value, want):  # value is a string; "unknown" handled per policy
        if value == "unknown":
            rule(name, False if unk_fail else None, "could not be determined")
        else:
            rule(name, value == want, f"is {value}, want {want}")

    if pol.get("require_enrolled") == "true":
        rule("require_enrolled", bool(st.get("enrolled")), f"enrolled={st.get('enrolled')}")
    if pol.get("require_self_heal") == "true":
        rule("require_self_heal", bool(st.get("self_heal")), f"self_heal={st.get('self_heal')}")
    if pol.get("require_disk_encryption") == "true":
        tri("require_disk_encryption", c.get("disk_encryption", "unknown"), "true")
    if pol.get("require_firewall") == "true":
        tri("require_firewall", c.get("firewall", "unknown"), "active")
    if pol.get("require_secure_boot") == "true":
        tri("require_secure_boot", c.get("secure_boot", "unknown"), "enabled")
    if pol.get("require_tpm2") == "true":
        tri("require_tpm2", c.get("tpm2", "unknown"), "present")
    if pol.get("forbid_autologin") == "true":
        rule("forbid_autologin", not st.get("autologin"), f"autologin={st.get('autologin')}")
    if "allowed_wheel_members" in pol:
        allowed = {x.strip() for x in pol["allowed_wheel_members"].split(",") if x.strip()}
        wheel = st.get("wheel_members", "")
        members = {x.strip() for x in (wheel if isinstance(wheel, str) else ",".join(wheel)).split(",") if x.strip()}
        extra = sorted(members - allowed)
        rule("allowed_wheel_members", not extra, f"unexpected wheel members: {', '.join(extra)}" if extra else "ok")
    if "max_screen_lock_seconds" in pol:
        v = c.get("screen_lock_seconds", "unknown")
        if v == "unknown":
            rule("max_screen_lock_seconds", False if unk_fail else None, "could not be determined")
        else:
            rule("max_screen_lock_seconds", int(v) <= int(pol["max_screen_lock_seconds"]), f"{v}s, max {pol['max_screen_lock_seconds']}s")
    if "required_login_mode" in pol:
        rule("required_login_mode", st.get("login_mode") == pol["required_login_mode"],
             f"login_mode={st.get('login_mode')}, want {pol['required_login_mode']}")
    return out


def main():
    args = [a for a in sys.argv[1:] if a != "--json"]
    as_json = "--json" in sys.argv
    if len(args) != 1:
        sys.exit(__doc__)
    try:
        pol = load_policy(args[0])
        st = json.load(sys.stdin)
    except (OSError, ValueError) as e:
        print(f"check: {e}", file=sys.stderr)
        sys.exit(2)
    if not pol:
        print("check: policy file has no rules", file=sys.stderr)
        sys.exit(2)
    res = evaluate(pol, st)
    failed = [r for r in res if r["result"] == "FAIL"]
    if as_json:
        print(json.dumps({"compliant": not failed, "results": res}))
    else:
        for r in res:
            print(f"{r['result']:<4} {r['rule']:<26} {r['detail']}")
        print("COMPLIANT" if not failed else f"NON-COMPLIANT ({len(failed)} failed)")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
