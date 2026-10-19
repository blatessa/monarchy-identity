#!/bin/bash
# The entra provider against a real test tenant: refused enrolls, enroll, sign-in on every service, the group policy,
# sudo, offline, leave. Opt-in: needs the himmelblau package in the VM and the tenant's details in the env file named
# by ENTRA_LAB_ENV (docs/dev/testing.md); without them it says so and exits 0.
source "$(dirname "$0")/lib.sh"
if [[ -z ${ENTRA_LAB_ENV:-} || ! -r ${ENTRA_LAB_ENV:-} ]]; then echo "SKIP: no Entra test tenant (set ENTRA_LAB_ENV; see docs/dev/testing.md)"; exit 0; fi
source "$ENTRA_LAB_ENV"
for v in ENTRA_TENANT ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET ENTRA_ALICE ENTRA_ALICE_PASSWORD ENTRA_BOB ENTRA_BOB_PASSWORD ENTRA_CAROL ENTRA_CAROL_PASSWORD; do
  [[ -n ${!v:-} ]] || { echo "SKIP: $ENTRA_LAB_ENV has no $v"; exit 0; }
done
SECRET=/root/entra-secret
E="enroll entra --tenant $ENTRA_TENANT --client-id $ENTRA_CLIENT_ID --password-file $SECRET"
ecli() { "${V[@]}" "sudo ~/oi/bin/monarchy-identity $*" 2>&1; }
# Every run registers the VM again; delete the device objects it leaves (needs az signed in to the tenant).
devices_cleanup() {
  command -v az >/dev/null || { echo "  NOTE: delete the device 'oi-client' in the Entra admin center"; return; }
  local id; for id in $(az rest --method get --url "https://graph.microsoft.com/v1.0/devices?\$filter=displayName eq 'oi-client'&\$select=id" --query 'value[].id' -o tsv 2>/dev/null); do
    az rest --method delete --url "https://graph.microsoft.com/v1.0/devices/$id" >/dev/null 2>&1; done
}
offline() { "${V[@]}" "sudo nft add table inet oi-offline; sudo nft add chain inet oi-offline out '{ type filter hook output priority 0; policy drop; }'; sudo nft add rule inet oi-offline out oif lo accept; sudo nft add rule inet oi-offline out ct state established accept"; }
online() { "${V[@]}" "sudo nft delete table inet oi-offline" 2>/dev/null; }
trap 'online; ecli leave >/dev/null; "${V[@]}" "sudo rm -f $SECRET"; devices_cleanup' EXIT

fresh
"${V[@]}" 'pacman -Q himmelblau' >/dev/null 2>&1 || { bad "himmelblau is not installed in the VM (build omacom/omarchy-pkgs pkgbuilds/himmelblau, pacman -U it)"; result; }
printf '%s\n' "$ENTRA_CLIENT_SECRET" | "${V[@]}" "sudo install -m 600 /dev/stdin $SECRET"
devices_cleanup

echo "[refused before anything changes]"
out=$(ecli enroll entra --tenant oi-no-such-tenant.onmicrosoft.com --client-id $ENTRA_CLIENT_ID --password-file $SECRET --groups linux-users)
[[ $out == *"Entra has no tenant named oi-no-such-tenant.onmicrosoft.com"* ]] && ok "an unknown tenant is refused" || bad "unknown tenant: $out"
out=$(ecli $E --groups linux-users,no-such-group)
[[ $out == *"Entra has no group or user named: no-such-group"* ]] && ok "an unknown group is refused" || bad "unknown group: $out"
"${V[@]}" '! grep -q himmelblau /etc/nsswitch.conf && ! grep -qs "managed by monarchy-identity" /etc/himmelblau/himmelblau.conf' && pam_stock && ok "  ... nothing changed" || bad "changed after a refusal"

echo "[enroll]"
out=$(ecli $E --groups linux-users --sudo-groups linux-admins)
[[ $out == *"enrolled in $ENTRA_TENANT"* ]] && ok "enroll entra" || { bad "enroll"; sed 's/^/      /' <<<"$out"; }
"${V[@]}" "! sudo grep -rqF $(q "$ENTRA_CLIENT_SECRET") /etc /var/lib/monarchy-identity" && ok "the client secret is not kept" || bad "secret on disk"

echo "[sign-in]"
expect ALLOWED "login: bob (in linux-users; registers the device)" login "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD" --session
expect ALLOWED "sddm: alice" sddm "$ENTRA_ALICE" "$ENTRA_ALICE_PASSWORD"
expect ALLOWED "lock screen: bob" omarchy-lock-password "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD"
expect DENIED  "login: carol (not in linux-users) is refused" login "$ENTRA_CAROL" "$ENTRA_CAROL_PASSWORD"
expect ALLOWED "login: tester (local) as before" login tester tester
# pam_himmelblau logs its re-prompt loop to stderr ahead of the result, so look at the result line only
out=$(pt sshd "$ENTRA_ALICE" "$ENTRA_ALICE_PASSWORD" | grep -E '^(ALLOWED|DENIED)')
[[ $out == DENIED* ]] && ok "ssh: alice with only a password is refused (Entra wants a second factor remotely)" || bad "ssh: alice (got: ${out:-<nothing>})"
expect ALLOWED "ssh: tester (local) as before" sshd tester tester
"${V[@]}" "h=\$(getent passwd $(q "$ENTRA_BOB") | cut -d: -f6); test -L \"\$h\" && test -d \"\$h/\"" && ok "bob's home directory, made by himmelblau" || bad "no home for bob"
"${V[@]}" "sudo sudo -l -U $(q "$ENTRA_ALICE") | grep -q '(ALL : ALL) ALL'" && ok "sudo: alice (linux-admins)" || bad "alice has no sudo"
! "${V[@]}" "sudo sudo -l -U $(q "$ENTRA_BOB") | grep -q '(ALL : ALL) ALL'" && ok "sudo: not bob" || bad "bob has sudo"
st=$(ecli status --json)
[[ $st == *'"himmelblaud_active":"true"'* && $st == *'"entra_reachable":"true"'* && $st == *'"pam_system_auth":"true"'* ]] && ok "status: healthy" || bad "status: $st"

echo "[offline]"
offline
expect ALLOWED "lock screen: bob with no network (cached)" omarchy-lock-password "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD"
expect ALLOWED "login: bob with no network" login "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD"
expect ALLOWED "login: tester with no network" login tester tester
online

echo "[leave]"
out=$(ecli leave)
[[ $out == *"stays registered in Entra"* ]] && ok "leave says the device stays in Entra" || bad "leave: $out"
pam_stock && "${V[@]}" '! grep -q himmelblau /etc/nsswitch.conf && ! test -e /etc/himmelblau/himmelblau.conf && ! systemctl is-active --quiet himmelblaud' \
  && ok "PAM stock, nsswitch clean, config gone, daemon stopped" || bad "leftovers after leave"
expect ALLOWED "login: tester after leave" login tester tester

echo "[enroll again after leave]"   # leave must clear what himmelblau kept, or the daemon wedges on stale tokens
devices_cleanup
out=$(ecli $E --groups linux-users)
[[ $out == *"enrolled in $ENTRA_TENANT"* ]] && ok "enroll entra again" || { bad "re-enroll"; sed 's/^/      /' <<<"$out"; }
expect ALLOWED "login: bob after re-enrolling" login "$ENTRA_BOB" "$ENTRA_BOB_PASSWORD"
result
