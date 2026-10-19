#!/bin/bash
# The entra provider against stubs (aad-tool, systemctl, and test/unit/stubs/entra-graph for Entra itself):
# what enroll refuses before changing anything, the files it writes, the policy, status, reassert and leave.
# Whether himmelblau then signs anyone in is the lab's job (test/vm/e2e-entra.sh).
source "$(dirname "$0")/lib.sh"
sandbox
export MONARCHY_IDENTITY_ENTRA_GRAPH="$REPO/test/unit/stubs/entra-graph"
export STUB_TENANT=corp.onmicrosoft.com STUB_CLIENT_ID=11111111-2222-3333-4444-555555555555
export STUB_ENTRA_GROUPS="linux-users=aaaaaaaa-0000-0000-0000-000000000001,linux-admins=aaaaaaaa-0000-0000-0000-000000000002"
export STUB_ENTRA_USERS="alice@corp.onmicrosoft.com,bob@corp.onmicrosoft.com"
unset STUB_NO_HIMMELBLAU STUB_HB_DOWN STUB_ENTRA_DOWN
HB=$T/etc/himmelblau/himmelblau.conf.d/50-monarchy-identity.conf SA=$T/etc/pam.d/system-auth
E=(enroll entra --tenant corp.onmicrosoft.com --client-id "$STUB_CLIENT_ID")
hb() { grep -sE "^$1 *=" "$HB" | sed 's/^[^=]*= *//'; }

echo "[refused before anything changes]"
BEFORE=$(snap)
oi enroll entra --groups linux-users;                         refused "no tenant"           "--tenant is required"
oi enroll entra --tenant 'corp;x' --groups linux-users;       refused "bad tenant"          "invalid --tenant"
oi "${E[@]:0:4}" --client-id nope --groups linux-users;       refused "bad client id"       "invalid --client-id"
oi "${E[@]}" --groups linux-users --offline-days 7;           refused "offline days"        "can't limit how long offline"
STUB_NO_HIMMELBLAU=1 oi "${E[@]}" --groups linux-users;       refused "client not installed" "sudo pacman -S himmelblau"
oi enroll entra --tenant other.onmicrosoft.com --client-id "$STUB_CLIENT_ID" --groups linux-users; refused "unknown tenant" "Entra has no tenant named other.onmicrosoft.com"
STUB_ENTRA_DOWN=1 oi "${E[@]}" --groups linux-users;          refused "Entra unreachable"   "cannot reach Entra ID"
oi enroll entra --tenant corp.onmicrosoft.com --groups linux-users; refused "groups need the app registration" "--client-id is required"
PWIN=wrong oi "${E[@]}" --groups linux-users;                 refused "wrong secret"        "the client secret is wrong"
oi "${E[@]}" --groups linux-users,nobody;                     refused "unknown group"       "Entra has no group or user named: nobody"
oi "${E[@]}" --users alice,mallory;                           refused "unknown user"        "mallory@corp.onmicrosoft.com"
[[ ! -e $MONARCHY_IDENTITY_STATE ]] && ok "nothing recorded" || bad "state written"

echo "[enroll with groups]"
oi "${E[@]}" --groups linux-users --sudo-groups linux-admins
[[ $RC -eq 0 && $OUT == *"enrolled in corp.onmicrosoft.com (login mode: groups)"* ]] && ok "enrolled" || { bad "enroll"; sed 's/^/      /' <<<"$OUT"; }
[[ $(hb domain) == corp.onmicrosoft.com && $(hb pam_allow_groups) == aaaaaaaa-0000-0000-0000-000000000001 ]] && ok "himmelblau.conf: tenant, allowed group by id" || bad "conf: $(cat "$HB")"
[[ $(hb enable_hello) == false && $(sed -n '/offline_breakglass/,$p' "$HB" | hb enabled) == true ]] && grep -qF "$(head -1 <<<"# managed by monarchy-identity")" "$HB" \
  && ok "password sign-in, offline cache on, marked as ours" || bad "conf: $(cat "$HB")"
[[ $(grep -c '\bhimmelblau\b' "$T/etc/nsswitch.conf") == 3 ]] && ok "nsswitch: passwd, group, shadow" || bad "nsswitch: $(cat "$T/etc/nsswitch.conf")"
[[ -e $STUB_STATE/himmelblaud-active && -e $STUB_STATE/himmelblaud-tasks-active ]] && ok "both daemons running" || bad "daemons"
grep -qF -- '-auth      [success=3 default=ignore]  pam_himmelblau.so ignore_unknown_user set_authtok' "$SA" && has_pam omarchy-lock-password \
  && ok "pam_himmelblau in system-auth and the lock screen" || bad "PAM: $(grep himmelblau "$SA")"
! grep -q pam_mkhomedir "$SA" && [[ ! -e $T/etc/pam.d/monarchy-identity-expired ]] \
  && ok "no pam_mkhomedir, no expired-password screen (himmelblau does both its own way)" || bad "extras applied"
grep -qF -- "-auth      [success=done default=ignore]  pam_exec.so quiet stdout expose_authtok $REPO/lib/login-steps" "$T/etc/pam.d/sddm" \
  && [[ $(grep -v '^#' "$T/etc/pam.d/monarchy-identity-login-steps") == 'auth     required  pam_himmelblau.so ignore_unknown_user set_authtok' ]] \
  && [[ ! -e $T/etc/sddm.conf.d/zz-monarchy-identity-session.conf ]] \
  && ok "the login screen asks Entra once, through its own service (codes and numbers there too)" || bad "login steps: $(cat "$T/etc/pam.d/sddm")"
[[ $(cat "$MONARCHY_IDENTITY_SUDOERS") == *"%linux-admins ALL=(ALL:ALL) ALL" ]] && ok "core: sudo for the admin group" || bad "sudoers"
[[ $(st provider) == entra && $(st tenant) == corp.onmicrosoft.com && $(st group_ids) == linux-users=aaaaaaaa-0000-0000-0000-000000000001 ]] && ok "state: tenant and the looked-up group id" || bad "state: $(cat "$MONARCHY_IDENTITY_STATE")"
! grep -rqF -- "$PW" "$T/etc" "$T/var" && ok "the client secret is stored nowhere" || bad "secret written to disk"

echo "[policy]"
: > "$STUB_LOG"; PWIN="" oi policy set --groups linux-users </dev/null
[[ $RC -eq 0 ]] && ! called "entra-graph resolve" && ok "same group again: no secret, no lookup" || bad "unchanged policy needed Entra: $OUT"
: > "$STUB_LOG"; oi policy set --groups linux-users,linux-admins
called "entra-graph resolve" && [[ $(hb pam_allow_groups) == aaaaaaaa-0000-0000-0000-000000000001,aaaaaaaa-0000-0000-0000-000000000002 ]] \
  && ok "a new group is looked up with the secret" || bad "new group: $OUT / $(hb pam_allow_groups)"
BEFORE=$(snap); oi policy set --groups linux-users,ghosts;    refused "a group Entra doesn't have" "no group or user named: ghosts"
oi policy set --users alice
[[ $(hb pam_allow_groups) == alice@corp.onmicrosoft.com ]] && ok "--users: a bare name gets the tenant's domain" || bad "users: $(hb pam_allow_groups)"
oi policy set --mode any
[[ -z $(hb pam_allow_groups) && $(cfg login_mode) == any ]] && ok "--mode any: no group limit" || bad "any: $(cat "$HB")"
oi policy set --groups linux-users
oi_user policy show; [[ $OUT == *"tenant:        corp.onmicrosoft.com"* ]] && ok "policy show: the tenant" || bad "show: $OUT"
: > "$STUB_LOG"; oi "${E[@]}" --groups linux-users --if-needed
[[ $RC -eq 0 && $OUT == *"already enrolled in corp.onmicrosoft.com"* ]] && ! called "entra-graph discover" && ok "--if-needed: no re-enrollment" || bad "if-needed: $OUT"
BEFORE=$(snap); oi enroll entra --tenant other.onmicrosoft.com --groups linux-users --if-needed; refused "--if-needed, other tenant" "already enrolled in 'corp.onmicrosoft.com'"
BEFORE=$(snap); STUB_OTHER_TENANT=other.onmicrosoft.com oi enroll entra --tenant other.onmicrosoft.com --client-id "$STUB_CLIENT_ID" --groups linux-users
refused "another tenant without leave" "already enrolled in 'corp.onmicrosoft.com'"
: > "$STUB_LOG"; oi "${E[@]}" --groups linux-users
[[ $RC -eq 0 && $OUT == *"enrolled in corp.onmicrosoft.com"* ]] && [[ $(hb pam_allow_groups) == aaaaaaaa-0000-0000-0000-000000000001 ]] \
  && ok "enroll again, same tenant: picks up as enrolled" || bad "re-enroll: $OUT"

echo "[status and reassert]"
oi status --json
python3 -I -c 'import json,sys; d=json.loads(sys.argv[1])["details"]; assert d=={"himmelblaud_active":"true","nss_himmelblau":"true","entra_reachable":"true","pam_system_auth":"true","pam_omarchy_lock_password":"true","pam_sddm":"true"}, d' "$OUT" \
  && ok "status: himmelblau's health and the PAM checks" || bad "status: $OUT"
printf 'passwd: files systemd\ngroup: files [SUCCESS=merge] systemd\nshadow: files systemd\nhosts: files dns\n' > "$T/etc/nsswitch.conf"
cp "$FIX/pam.d/system-auth" "$SA"; cp "$FIX/pam.d/sddm" "$T/etc/pam.d/sddm"; rm -f "$STUB_STATE/himmelblaud-active"
oi reassert
[[ $(grep -c '\bhimmelblau\b' "$T/etc/nsswitch.conf") == 3 ]] && grep -q pam_himmelblau "$SA" && grep -q login-steps "$T/etc/pam.d/sddm" && [[ -e $STUB_STATE/himmelblaud-active ]] \
  && ok "reassert: nsswitch, PAM (the login screen's too) and the daemon back" || bad "reassert: $OUT"
oi reassert; [[ $(grep -c '\bhimmelblau\b' "$T/etc/nsswitch.conf") == 3 && $(grep -c 'BEGIN monarchy' "$SA") == 4 ]] && ok "reassert is idempotent" || bad "duplicated edits"

echo "[leave]"
mkdir -p "$T/himmelblaud"; printf '[corp.onmicrosoft.com]\ndevice_id = 0d1ce000-0000-4000-8000-00000000abcd\n' > "$T/himmelblaud/himmelblau.conf"   # what the first sign-in leaves
: > "$STUB_LOG"; oi leave
[[ $RC -eq 0 ]] && called "aad-tool cache-clear --full" && called "systemctl clean --what=fdstore --what=state --what=cache himmelblaud himmelblaud-tasks" \
  && ok "forgets the device registration, cached accounts and stored tokens" || bad "leave: $OUT / $(cat "$STUB_LOG")"
[[ $OUT == *"(device ID 0d1ce000-0000-4000-8000-00000000abcd) stays registered in Entra"* ]] && ok "says the device stays in Entra, and which one" || bad "no device note: $OUT"
cmp -s "$SA" "$FIX/pam.d/system-auth" && cmp -s "$T/etc/pam.d/sddm" "$FIX/pam.d/sddm" && ! grep -q himmelblau "$T/etc/nsswitch.conf" && [[ ! -e $HB && ! -e $STUB_STATE/himmelblaud-active && ! -e $MONARCHY_IDENTITY_STATE ]] \
  && [[ ! -e $T/etc/pam.d/monarchy-identity-login-steps ]] \
  && [[ ! -e $T/etc/himmelblau/himmelblau.conf.d ]] && ok "PAM stock, nsswitch clean, config gone, daemons stopped, not enrolled" || bad "leftovers"
oi "${E[@]}" --groups linux-users; oi leave   # nobody signed in: never registered
[[ $RC -eq 0 && $OUT != *"stays registered"* ]] && ok "never registered: no device to delete, says nothing about one" || bad "leave unregistered: $OUT"
result
