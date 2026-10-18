#!/bin/bash
# `status --json` is the interface other tools build on: valid JSON, the documented fields, details that follow reality.
source "$(dirname "$0")/lib.sh"
sandbox
js() { printf '%s' "$OUT" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); r=eval(sys.argv[1]); print(*r) if isinstance(r,tuple) else print(r)' "$1" 2>&1; }

echo "[not enrolled]"
oi_user status --json
[[ $(js 'sorted(d)') == "['autologin', 'details', 'enrolled', 'login_mode', 'login_theme', 'provider', 'schema', 'username_field']" ]] && ok "top-level fields" || bad "fields: $OUT"
[[ $(js 'd["schema"], d["enrolled"], d["provider"], d["login_mode"], d["details"]') == "2 False local none {}" ]] && ok "schema 2, not enrolled, provider local, no details" || bad "values: $OUT"
[[ $(js 'd["autologin"]') == True ]] && ok "autologin reflects Omarchy's stock config" || bad "autologin"
[[ $(js 'd["login_theme"], d["username_field"]') == "omarchy False" ]] && ok "stock theme, no username field" || bad "theme"
oi_user status; [[ $OUT == *"enrolled:        false"* && $OUT == *"provider:        local"* ]] && ok "plain status" || bad "plain: $OUT"

echo "[enrolled]"
mkdir -p "$T/themes/monarchy-identity"; touch "$T/themes/monarchy-identity/Main.qml"
enroll --groups oi-laptop-users >/dev/null
oi status --json
[[ $(js 'd["enrolled"], d["provider"], d["login_mode"], d["autologin"], d["login_theme"], d["username_field"]') == "True ad groups False monarchy-identity True" ]] && ok "enrolled, ad, groups, autologin off, our theme" || bad "values: $OUT"
[[ $(js 'sorted(d["details"])') == "['domain_joined', 'nss_sss', 'pam_omarchy_lock_password', 'pam_sddm', 'pam_system_auth', 'sssd_active']" ]] && ok "details fields" || bad "details: $OUT"
[[ $(js 'set(d["details"].values())') == "{'true'}" ]] && ok "every check true on a healthy machine" || bad "checks: $(js 'd["details"]')"
oi_user status --json; [[ $(js 'd["details"]["domain_joined"]') == unknown ]] && ok "domain_joined is unknown without root" || bad "non-root details: $OUT"

echo "[details follow reality]"
python3 -I "$REPO/lib/pamedit.py" remove "$T/etc/pam.d/system-auth"; sed -i -E '/^(passwd|group|shadow):/ s/[[:space:]]+sss\b//' "$T/etc/nsswitch.conf"
rm -f "$STUB_STATE/sssd-active" "$STUB_STATE/joined"
oi status --json
[[ $(js 'd["details"]["pam_system_auth"], d["details"]["nss_sss"], d["details"]["sssd_active"], d["details"]["domain_joined"], d["details"]["pam_omarchy_lock_password"]') == "false false false false true" ]] && ok "each broken piece shows false, intact ones stay true" || bad "details: $(js 'd["details"]')"
oi leave; oi status --json
[[ $(js 'd["enrolled"], d["provider"], d["details"]') == "False local {}" ]] && ok "after leave: not enrolled" || bad "after leave: $OUT"
result
