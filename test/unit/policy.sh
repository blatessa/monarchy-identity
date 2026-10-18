#!/bin/bash
# Who may sign in, as written to disk: implied modes, `policy set` changing only what's passed, refusals that change
# nothing, `enroll --if-needed`, the generated sssd.conf and sudoers. Whether sssd then enforces it is the lab's job.
source "$(dirname "$0")/lib.sh"
sandbox
SSSD="$T/etc/sssd/sssd.conf"; SUDOERS=$MONARCHY_IDENTITY_SUDOERS
conf() { grep -qxF -- "$1" "$SSSD"; }
autologin_user() { (source "$REPO/lib/common.sh"; sddm_autologin_user); }   # the effective SDDM autologin user

echo "[enroll: --groups alone implies the mode; autologin off by default]"
[[ -n $(autologin_user) ]] && ok "before: Omarchy autologin on (fixture)" || bad "fixture has no autologin"
enroll --groups oi-laptop-users --sudo-groups oi-admins
[[ $OUT == *"enrolled in CORP.TEST"* && $OUT == *"login mode: groups"* ]] && ok "enrolled, mode groups" || { bad "enroll"; sed 's/^/      /' <<<"$OUT"; }
conf "access_provider = simple" && conf "simple_allow_groups = oi-laptop-users" && ok "sssd.conf: simple access, the group" || bad "sssd.conf access"
[[ $(stat -c %a "$SSSD") == 600 ]] && ok "sssd.conf is 0600" || bad "sssd.conf mode"
[[ $(cat "$SUDOERS") == *"%oi-admins ALL=(ALL:ALL) ALL" && $(stat -c %a "$SUDOERS") == 440 ]] && ok "sudoers drop-in 0440 with the group" || bad "sudoers: $(cat "$SUDOERS")"
called "visudo -cf" && ok "sudoers validated with visudo before install" || bad "no visudo run"
THEME_SUDOERS=$T/etc/sudoers.d/51-monarchy-identity-theme
[[ $(sed -n 2p "$THEME_SUDOERS") == "%oi-laptop-users ALL=(root) NOPASSWD: /usr/bin/omarchy-theme-set-browser-policy [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]" \
  && $(stat -c %a "$THEME_SUDOERS") == 440 ]] && ok "theme rule: the sign-in group, only Omarchy's browser-policy helper, six hex digits" || bad "theme sudoers: $(cat "$THEME_SUDOERS")"
POLKIT=$T/etc/polkit-1/rules.d/49-monarchy-identity.rules
# admins_for USER GROUP...: the identities the generated rule offers when USER (in GROUPs) asks; polkit runs it as plain JS
admins_for() { node -e 'let f; const polkit = { addAdminRule: g => f = g }; eval(require("fs").readFileSync(process.argv[1], "utf8"));
  const [user, ...groups] = process.argv.slice(2); console.log(f({}, { user, isInGroup: g => groups.includes(g) }).join(" "))' "$POLKIT" "$@"; }
[[ $(stat -c %a "$POLKIT") == 644 && $(admins_for bob oi-laptop-users) == "unix-group:wheel unix-group:oi-admins" ]] \
  && ok "polkit: sudo group may answer admin prompts, wheel kept (ours sorts before polkit's 50-default)" || bad "polkit rule: $(cat "$POLKIT")"
[[ $(admins_for alice oi-admins) == "unix-user:alice unix-group:wheel unix-group:oi-admins" && $(admins_for brady wheel) == "unix-user:brady "* ]] \
  && ok "polkit: an admin who asks is offered first (Omarchy's prompt asks for the first)" || bad "polkit order: $(admins_for alice oi-admins)"
[[ -z $(autologin_user) ]] && ok "autologin turned off" || bad "autologin still on"
[[ $(cfg login_mode) == groups && $(cfg groups) == oi-laptop-users && $(cfg sudo_groups) == oi-admins ]] && ok "config.toml records the policy" || bad "config.toml: $(cat "$MONARCHY_IDENTITY_CONF")"
oi policy show; [[ $OUT == *"login mode:    groups"* ]] && ok "policy show works" || bad "policy show: $OUT"
oi_user policy show; [[ $OUT == *"login mode:    groups"* ]] && ok "policy show works without root" || bad "policy show (user): $OUT"

echo "[reassert restores deleted drop-ins]"
rm -f "$SUDOERS" "$T/etc/sddm.conf.d/zz-monarchy-identity.conf"
oi reassert
[[ -f $SUDOERS && -f $T/etc/sddm.conf.d/zz-monarchy-identity.conf ]] && ok "sudo and autologin override back" || bad "reassert: $OUT"

echo "[policy set: --users alone implies assigned; only what's passed changes]"
: > "$STUB_LOG"; oi policy set --users alice
[[ $OUT == *"mode=assigned"* ]] && conf "simple_allow_users = alice" && ok "policy set --users" || bad "policy set --users: $OUT"
[[ $(st realm) == CORP.TEST && $(cfg sudo_groups) == oi-admins && -f $SUDOERS ]] && ok "realm and sudo untouched by a change that didn't mention them" || bad "state lost"
! called "net ads join" && ok "no re-join" || bad "re-joined"

echo "[policy set: any, offline days]"
oi policy set --mode any --offline-days 3
conf "access_provider = permit" && conf "offline_credentials_expiration = 3" && ok "any + offline_credentials_expiration = 3" || bad "any/offline"
oi policy set --mode any --offline-days 0
grep -q offline_credentials_expiration "$SSSD" && bad "0 days still written" || ok "0 days (never) writes nothing"

echo "[policy set: back to groups, sudo removed]"
oi policy set --groups oi-laptop-users --sudo-groups -
[[ ! -e $POLKIT ]] && ok "--sudo-groups -: polkit rule removed too" || bad "polkit rule left"
conf "simple_allow_groups = oi-laptop-users" && [[ ! -e $SUDOERS ]] && ok "--sudo-groups - removed sudo" || bad "sudo not removed"
oi reassert; [[ ! -e $SUDOERS ]] && ok "reassert doesn't bring removed sudo back" || bad "sudo came back"

echo "[refused changes change nothing]"
BEFORE=$(snap)
oi policy set --mode groups --groups '';       refused "no groups"        "needs --groups"
oi policy set --groups 'bad;group';            refused "invalid group"    "invalid --groups"
oi policy set --groups no-such-group;          refused "unknown group"    "has no group named"
oi policy set --mode bogus;                    refused "bogus mode"       "bad --mode"
oi policy set --offline-days abc;              refused "bad offline-days" "invalid --offline-days"
oi policy set --sudo-groups 'x y';             refused "bad sudo-groups"  "invalid --sudo-groups"
oi policy set --mode assigned --users '';     refused "assigned, no users" "needs --users"
oi policy set --frob;                          refused "unknown option"   "unknown option"
oi_user policy set --mode any;                 [[ $OUT == *"administrator rights"* ]] && ok "non-root refused" || bad "non-root: $OUT"
[[ $(snap) == "$BEFORE" ]] && ok "policy unchanged" || bad "policy changed"
STUB_VISUDO_FAIL=1 oi policy set --sudo-groups oi-admins
[[ $OUT == *"failed validation"* && ! -e $SUDOERS ]] && ok "sudoers visudo rejects: nothing installed" || bad "visudo failure: $OUT"
ls "$T/etc/sudoers.d" | grep -q '\.' && bad "temp sudoers file left behind" || ok "no stray file in sudoers.d"

echo "[sssd restarts go through reset-failed]"
: > "$STUB_LOG"; oi policy set --mode any
awk '/reset-failed/{r=NR} /restart/{s=NR} END{exit !(r && s && r<s)}' "$STUB_LOG" && ok "reset-failed before every restart" || bad "restart without reset-failed"

echo "[enroll --if-needed]"
oi policy set --groups oi-laptop-users; : > "$STUB_LOG"
enroll --groups oi-admins --if-needed
[[ $OUT == *"converging policy without re-joining"* ]] && conf "simple_allow_groups = oi-admins" && ! called "net ads join" && ok "enrolled machine: converged, not re-joined" || bad "if-needed: $OUT"
BEFORE=$(snap)
oi enroll --realm OTHER.EXAMPLE --groups g --if-needed; refused "different realm" "already enrolled in"
echo "[no polkit on the machine: nothing written, nothing refused]"
rm -rf "$T/etc/polkit-1"; oi policy set --sudo-groups oi-admins
[[ ! -e $T/etc/polkit-1 && $OUT == *"policy updated"* ]] && ok "no polkit rules directory: skipped, and not created" || bad "missing polkit dir: $OUT"
mkdir -p "$T/etc/polkit-1/rules.d"; oi reassert

echo "[theme rule follows who may sign in]"
oi policy set --users alice,bob.smith,'bad name'
[[ $(sed -n 2p "$THEME_SUDOERS") == "alice,bob.smith ALL=(root) NOPASSWD:"* ]] && ok "assigned users named; a name outside the safe set is skipped" || bad "assigned: $(cat "$THEME_SUDOERS")"
oi policy set --mode any
[[ ! -e $THEME_SUDOERS ]] && ok "--mode any: no theme rule (no one to name)" || bad "theme rule kept for mode any"
oi policy set --groups oi-laptop-users
[[ -f $THEME_SUDOERS ]] && ok "back to groups: rule is back" || bad "rule not restored"

echo "[leave turns autologin back on; --if-needed on a fresh machine enrolls]"
oi leave
[[ -n $(autologin_user) ]] && ok "autologin back on" || bad "autologin not restored"
[[ ! -e $SUDOERS && ! -e $THEME_SUDOERS && ! -e $POLKIT ]] && ok "sudoers and polkit drop-ins gone" || bad "sudoers/polkit left"
enroll --groups oi-laptop-users --if-needed --keep-autologin
[[ $OUT == *"enrolled in"* && -n $(autologin_user) ]] && ok "--keep-autologin keeps it" || bad "keep-autologin: $OUT"
result
