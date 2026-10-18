#!/bin/bash
# The provider contract, with a stub provider (test/unit/stub-provider) installed next to ad: the core parses and
# validates the shared options and runs the shared steps; the provider gets only its own options and the resolved
# policy, and its PAM module is the one inserted. Nothing here is AD.
source "$(dirname "$0")/lib.sh"
sandbox
R=$T/root; mkdir -p "$R/providers"; ln -s "$REPO/lib" "$R/lib"
ln -s "$REPO/providers/ad" "$R/providers/ad"; ln -s "$REPO/test/unit/stub-provider" "$R/providers/stub"
export MONARCHY_IDENTITY_ROOT=$R
SA=$T/etc/pam.d/system-auth
seen() { grep -qxF -- "stub $1" "$STUB_LOG"; }   # seen 'ACTION ARGS | mode|groups|users|offline_days|password_file'
autologin_user() { (source "$REPO/lib/common.sh"; sddm_autologin_user); }

echo "[before enrolling: refused by the core, the provider never runs]"
BEFORE=$(snap)
oi enroll --tenant acme --groups staff;               refused "two providers, none named" "name the directory provider"
oi enroll nosuch --groups staff;                      refused "unknown provider"          "no provider named 'nosuch'"
oi enroll stub --tenant acme;                         refused "no policy"                 "say who may sign in"
oi enroll stub --tenant acme --groups 'a;b';          refused "invalid group"             "invalid --groups"
oi enroll stub --tenant acme --groups g --offline-days x; refused "bad offline-days"      "invalid --offline-days"
oi enroll stub --tenant acme --groups g --sudo-groups 'x y'; refused "bad sudo-groups"    "invalid --sudo-groups"
oi enroll stub --tenant acme --groups;                refused "option without a value"    "--groups needs a value"
! grep -q '^stub ' "$STUB_LOG" && ok "the stub was never called" || bad "stub called: $(cat "$STUB_LOG")"
STUB_REFUSE=1 oi enroll stub --tenant acme --groups g; refused "the directory says no"   "the stub directory says no"
[[ ! -e $MONARCHY_IDENTITY_CONF && ! -e $MONARCHY_IDENTITY_STATE ]] && ok "nothing recorded for a refused enrollment" || bad "config or state written"
oi_user enroll --help
[[ $RC -eq 0 && $OUT == *"--groups a,b"* && $OUT == *"Providers: ad,stub"* ]] && ok "enroll --help: shared options, the providers" || bad "help: $OUT"
oi_user enroll stub --help; [[ $OUT == *"--tenant T"* && $OUT == *"--sudo-groups"* ]] && ok "enroll stub --help adds the stub's options" || bad "stub help: $OUT"

echo "[enroll]"
: > "$STUB_LOG"
oi enroll stub --tenant acme --groups staff --sudo-groups oi-admins --offline-days 7 --password-file "$T/pw"
[[ $RC -eq 0 && $OUT == *"enrolled in acme (login mode: groups)"* ]] && ok "enrolled" || { bad "enroll"; sed 's/^/      /' <<<"$OUT"; }
seen "enroll --tenant acme | groups|staff||7|$T/pw" && ok "provider got only --tenant, plus the resolved policy and password file" || bad "stub saw: $(cat "$STUB_LOG")"
grep -qF -- '-auth      [success=3 default=ignore]  pam_stub.so try_first_pass' "$SA" && has_pam omarchy-lock-password \
  && ok "the stub's PAM module, with its arguments, in both services" || bad "PAM: $(grep -A1 BEGIN "$SA")"
! grep -q pam_sss "$T"/etc/pam.d/* && ok "no pam_sss anywhere" || bad "pam_sss inserted"
[[ $(cat "$MONARCHY_IDENTITY_SUDOERS") == *"%oi-admins ALL=(ALL:ALL) ALL" && -z $(autologin_user) ]] && ok "core: sudoers and autologin off" || bad "sudo/autologin"
[[ $(st provider) == stub && $(st tenant) == acme && $(cfg login_mode) == groups && $(cfg offline_days) == 7 ]] && ok "state: the provider and the stub's keys; config: the policy" || bad "config: $(cat "$MONARCHY_IDENTITY_CONF" "$MONARCHY_IDENTITY_STATE")"
[[ -z $(cfg provider) && -z $(cfg tenant) && -z $(st login_mode) ]] && ok "neither file holds the other's keys" || bad "keys mixed"
[[ ! -e $T/etc/sssd/sssd.conf ]] && ! grep -q sss "$T/etc/nsswitch.conf" && ok "nothing of ad's (sssd, nsswitch)" || bad "ad-specific files written"
BEFORE=$(snap)
oi enroll ad --realm CORP.TEST --groups staff;        refused "another provider while enrolled" "already enrolled with 'stub'"

echo "[an MDM rewriting config.toml with only the policy leaves the enrollment alone]"
printf 'login_mode = "groups"\ngroups = "staff"\nsudo_groups = "oi-admins"\noffline_days = "7"\n' > "$MONARCHY_IDENTITY_CONF"
oi status --json; [[ $OUT == *'"enrolled":true'*'"provider":"stub"'* ]] && ok "still enrolled" || bad "status after an MDM write: $OUT"
oi_user policy show; [[ $OUT == *"tenant:        acme"* ]] && ok "the stub still reads its own state" || bad "show: $OUT"

echo "[policy, status, reassert]"
: > "$STUB_LOG"; oi policy set --users alice
seen "policy apply | assigned|staff|alice|7|" && [[ $(cfg login_mode) == assigned && -f $MONARCHY_IDENTITY_SUDOERS ]] && ok "policy set: provider applies the merged policy, sudo kept" || bad "policy set: $OUT / $(cat "$STUB_LOG")"
oi_user policy show; [[ $OUT == *"tenant:        acme"* && $OUT == *"login mode:    assigned"* ]] && ok "policy show: the stub's line and the core's" || bad "show: $OUT"
: > "$STUB_LOG"; oi enroll stub --tenant acme --groups staff --if-needed
grep -q '^stub matches --tenant acme' "$STUB_LOG" && ! grep -q '^stub enroll' "$STUB_LOG" && seen "policy apply | groups|staff||0|" \
  && ok "--if-needed: matched, converged, not re-enrolled" || bad "if-needed: $(cat "$STUB_LOG")"
[[ ! -e $MONARCHY_IDENTITY_SUDOERS ]] && ok "--if-needed converges to exactly what was asked (no sudo)" || bad "sudo left"
oi status --json
python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["provider"]=="stub" and d["details"]=={"stub_reachable":"true","pam_system_auth":"true","pam_omarchy_lock_password":"true","pam_sddm":"true"}' "$OUT" \
  && ok "status: the stub's details and the core's PAM checks" || bad "status: $OUT"
grep -qx 'auth     required  pam_stub.so' "$T/etc/pam.d/monarchy-identity-expired" && ok "the expired-password re-check uses the stub's module" || bad "expired service: $(cat "$T/etc/pam.d/monarchy-identity-expired")"
cp "$FIX/pam.d/system-auth" "$SA"; : > "$STUB_LOG"; oi reassert
grep -q 'pam_stub.so' "$SA" && grep -q '^stub reassert' "$STUB_LOG" && ok "reassert: provider called, the stub's PAM module back" || bad "reassert: $OUT"

echo "[leave]"
: > "$STUB_LOG"; oi leave --purge --quiet
seen "unenroll --purge | ||||" && ok "provider got its own leave options only" || bad "unenroll saw: $(cat "$STUB_LOG")"
cmp -s "$SA" "$FIX/pam.d/system-auth" && [[ -n $(autologin_user) && ! -e $MONARCHY_IDENTITY_STATE ]] && ok "PAM stock, autologin back, not enrolled" || bad "leave: $OUT"
result
