#!/bin/bash
# The entra provider against a real test tenant, with the released himmelblau (what people install): refused enrolls,
# enroll, sign-in on every service, the group policy, sudo, the login screen asking once (and saying why it refused)
# and an authenticator code there (an MFA user, optional), offline, enrolling again (registered, and after leave with
# the old device still in Entra), leave. Opt-in: needs the tenant's details in the env file named by ENTRA_LAB_ENV and
# the himmelblau package (docs/dev/testing.md); without a tenant it says so and exits 0.
source "$(dirname "$0")/lib.sh"
entra_lab || exit 0
SECRET=/root/entra-secret
E="enroll entra --tenant $ENTRA_TENANT --client-id $ENTRA_CLIENT_ID --password-file $SECRET"
ecli() { "${V[@]}" "sudo ~/oi/bin/monarchy-identity $*" 2>&1; }
device_id() { "${V[@]}" 'sudo sed -n "s/^device_id *= *//p" /var/cache/himmelblaud/himmelblau.conf'; }   # himmelblau's record
offline() { "${V[@]}" "sudo nft add table inet oi-offline; sudo nft add chain inet oi-offline out '{ type filter hook output priority 0; policy drop; }'; sudo nft add rule inet oi-offline out oif lo accept; sudo nft add rule inet oi-offline out ct state established accept"; }
online() { "${V[@]}" "sudo nft delete table inet oi-offline" 2>/dev/null; }
trap 'online; ecli leave >/dev/null; "${V[@]}" "sudo rm -f $SECRET"; entra_codes off; entra_devices_cleanup' EXIT

fresh
himmelblau_install || result
entra_codes
printf '%s\n' "$ENTRA_CLIENT_SECRET" | "${V[@]}" "sudo install -m 600 /dev/stdin $SECRET"
# a home made new from a skeleton with what stopped himmelblau's own copy: a file many levels deep and a dangling link
"${V[@]}" "sudo install -D /dev/null /etc/skel/.local/state/omarchy/oi/a/b/c/d/deep-marker; sudo ln -sfn /nonexistent /etc/skel/.oi-dangling; sudo rm -rf /home/bob"
entra_devices_cleanup

echo "[refused before anything changes]"
out=$(ecli enroll entra --tenant oi-no-such-tenant.onmicrosoft.com --client-id $ENTRA_CLIENT_ID --password-file $SECRET --groups linux-users)
[[ $out == *"Entra has no tenant named oi-no-such-tenant.onmicrosoft.com"* ]] && ok "an unknown tenant is refused" || bad "unknown tenant: $out"
out=$(ecli $E --groups linux-users,no-such-group)
[[ $out == *"Entra has no group or user named: no-such-group"* ]] && ok "an unknown group is refused" || bad "unknown group: $out"
"${V[@]}" '! grep -q himmelblau /etc/nsswitch.conf && ! grep -qs "managed by monarchy-identity" /etc/himmelblau/himmelblau.conf.d/50-monarchy-identity.conf' && pam_stock && ok "  ... nothing changed" || bad "changed after a refusal"

echo "[enroll]"
out=$(ecli $E --groups linux-users --sudo-groups linux-admins)
[[ $out == *"enrolled in $ENTRA_TENANT"* ]] && ok "enroll entra" || { bad "enroll"; sed 's/^/      /' <<<"$out"; }
"${V[@]}" "! sudo grep -rqF $(q "$ENTRA_CLIENT_SECRET") /etc /var/lib/monarchy-identity" && ok "the client secret is not kept" || bad "secret on disk"
"${V[@]}" 'pacman -Qii himmelblau | grep -qF "himmelblau.conf [unmodified]"' && ok "the himmelblau package's own config untouched (ours is a drop-in)" || bad "himmelblau.conf modified"

echo "[sign-in]"
expect ALLOWED "login: bob (in linux-users; registers the device)" login "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD" --session
expect ALLOWED "sddm: alice" sddm "$ENTRA_ALICE" "$ENTRA_ALICE_PASSWORD"
expect ALLOWED "sddm: bob by his short name" sddm "${ENTRA_BOB%@*}" "$ENTRA_BOB_PASSWORD"
expect ALLOWED "lock screen: bob" omarchy-lock-password "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD"
expect DENIED  "login: carol (not in linux-users) is refused" login "$ENTRA_CAROL" "$ENTRA_CAROL_PASSWORD"
out=$(pt sddm "$ENTRA_CAROL" "$ENTRA_CAROL_PASSWORD" --messages)
[[ $out == DENIED* && $out == *"MSG This account can't sign in on this laptop. Ask IT."* ]] \
  && ok "login screen: carol is told the account can't sign in here (himmelblau says Authentication failure)" || bad "carol at the login screen: $out"
expect ALLOWED "login: tester (local) as before" login tester tester
# pam_himmelblau logs its re-prompt loop to stderr ahead of the result, so look at the result line only
out=$(pt sshd "$ENTRA_ALICE" "$ENTRA_ALICE_PASSWORD" | grep -E '^(ALLOWED|DENIED)')
[[ $out == DENIED* ]] && ok "ssh: alice with only a password is refused (Entra wants a second factor remotely)" || bad "ssh: alice (got: ${out:-<nothing>})"
expect ALLOWED "ssh: tester (local) as before" sshd tester tester
"${V[@]}" "test \"\$(getent passwd $(q "$ENTRA_BOB") | cut -d: -f6)\" = /home/bob && test -d /home/bob && ! test -L /home/bob" && ok "bob's home is /home/bob" || bad "no /home/bob for bob"
"${V[@]}" "sudo test -e /home/bob/.local/state/omarchy/oi/a/b/c/d/deep-marker && sudo test -L /home/bob/.oi-dangling && test \$(sudo stat -c %U /home/bob/.local/state/omarchy/oi/a/b/c/d/deep-marker) = bob; sudo rm -rf /etc/skel/.oi-dangling /etc/skel/.local/state/omarchy/oi" && ok "bob's new home has all of /etc/skel (deep files, a dangling link), his own" || bad "bob's home is missing part of /etc/skel"
"${V[@]}" "sudo sudo -l -U $(q "$ENTRA_ALICE") | grep -q '(ALL : ALL) ALL'" && ok "sudo: alice (linux-admins)" || bad "alice has no sudo"
! "${V[@]}" "sudo sudo -l -U $(q "$ENTRA_BOB") | grep -q '(ALL : ALL) ALL'" && ok "sudo: not bob" || bad "bob has sudo"
# SDDM answers every prompt with the password it has, and pam_himmelblau starts over after a refusal: the login
# screen's own check asks Entra once (pamtest answers a repeated prompt once more, so a loop would show as a second try).
# Our theme sends the password and a code on two lines; pamtest gives that whole answer to SDDM's one prompt, as SDDM does.
echo "[the login screen: Entra asked once; a code there too]"
since=$(hb_mark)
out=$(pt --messages sddm "$ENTRA_BOB" "not-bobs-password-1")
[[ $out == DENIED* ]] && ok "sddm: bob with a wrong password is refused" || bad "bob, wrong password: $out"
[[ $out == *"MSG Error validating credentials"*"MSG monarchy-identity: refused"* && $out != *AADSTS* && $out != *PAM_CONV_ERR* ]] \
  && ok "  ... saying why, in Entra's words (no error code or IDs, no PAM noise)" || bad "bob, why: $out"
n=$(steps "$since"); [[ $n == 1 ]] && ok "  ... after one try (the password went to Entra once)" || bad "wrong password sent $n times"
expect DENIED "sddm: carol (not in linux-users) is refused" sddm "$ENTRA_CAROL" "$ENTRA_CAROL_PASSWORD"
expect ALLOWED "sddm: tester (local) as before" sddm tester tester
if [[ -n ${ENTRA_DAVE:-} && -n ${ENTRA_DAVE_PASSWORD:-} && -n ${ENTRA_DAVE_TOTP_SECRET:-} ]]; then
  # dave must give an authenticator code; this is his first sign-in on the laptop
  since=$(hb_mark)
  expect DENIED "sddm: dave (MFA, first sign-in here), password only: not yet, a code is wanted" sddm "$ENTRA_DAVE" "$ENTRA_DAVE_PASSWORD"
  n=$(steps "$since"); [[ $n == 1 ]] && ok "  ... and nothing was sent as the code" || bad "dave: $n steps for a password alone"
  since=$(hb_mark)
  expect DENIED "sddm: dave with a wrong code is refused" sddm "$ENTRA_DAVE" "$ENTRA_DAVE_PASSWORD"$'\n'000000
  n=$(steps "$since"); [[ $n == 2 ]] && ok "  ... the password and the code went to Entra once each" || bad "dave, wrong code: $n steps"
  since=$(hb_mark)
  expect ALLOWED "sddm: dave with his password and code" sddm "$ENTRA_DAVE" "$ENTRA_DAVE_PASSWORD"$'\n'"$(totp "$ENTRA_DAVE_TOTP_SECRET")"
  hb_log "$since" | grep -q OathCodeIncorrect \
    && echo "      Entra refused the code: ENTRA_DAVE_TOTP_SECRET isn't dave's authenticator key any more (docs/dev/testing.md)"
  expect ALLOWED "sddm: dave again, password only (Entra remembers this laptop)" sddm "$ENTRA_DAVE" "$ENTRA_DAVE_PASSWORD"
else
  echo "  SKIP the code: $ENTRA_LAB_ENV has no ENTRA_DAVE, ENTRA_DAVE_PASSWORD, ENTRA_DAVE_TOTP_SECRET (an MFA user)"
fi
st=$(ecli status --json)
[[ $st == *'"himmelblaud_active":"true"'* && $st == *'"entra_reachable":"true"'* && $st == *'"pam_system_auth":"true"'* && $st == *'"pam_sddm":"true"'* ]] && ok "status: healthy" || bad "status: $st"

echo "[enroll again: the laptop keeps its registration]"
d1=$(device_id); [[ -n $d1 ]] || bad "no device id after the first sign-in"
out=$(ecli $E --groups linux-users --sudo-groups linux-admins)
[[ $out == *"enrolled in $ENTRA_TENANT"* && $(device_id) == "$d1" ]] && ok "enroll entra again: same device" || bad "re-enroll: $(device_id) vs $d1: $out"
expect ALLOWED "login: bob after enrolling again" login "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD"

echo "[offline]"
offline
expect ALLOWED "lock screen: bob with no network (cached)" omarchy-lock-password "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD"
expect ALLOWED "login: bob with no network" login "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD"
expect ALLOWED "login: tester with no network" login tester tester
online

echo "[leave]"
out=$(ecli leave)
[[ $out == *"(device ID $d1) stays registered in Entra"* ]] && ok "leave says the device stays in Entra, and which" || bad "leave: $out"
pam_stock && "${V[@]}" '! grep -q himmelblau /etc/nsswitch.conf && ! test -e /etc/himmelblau/himmelblau.conf.d/50-monarchy-identity.conf && ! systemctl is-active --quiet himmelblaud' \
  && ok "PAM stock, nsswitch clean, config gone, daemon stopped" || bad "leftovers after leave"
expect ALLOWED "login: tester after leave" login tester tester

# A reinstalled laptop: its old device is still in Entra under the same name. leave must also clear what himmelblau
# kept, or the daemon wedges on stale tokens.
echo "[enroll again after leave, the old device still in Entra]"
out=$(ecli $E --groups linux-users)
[[ $out == *"enrolled in $ENTRA_TENANT"* ]] && ok "enroll entra again" || { bad "re-enroll"; sed 's/^/      /' <<<"$out"; }
expect ALLOWED "login: bob after re-enrolling" login "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD" --session
d2=$(device_id); [[ -n $d2 && $d2 != "$d1" ]] && ok "registered as a new device" || bad "device id after re-enroll: '$d2' (was $d1)"

result
