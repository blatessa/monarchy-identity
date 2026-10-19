#!/bin/bash
# An expired password or a second sign-in step at the login screen: the helpers' marks, and the session command's
# choices (desktop, the change or second-step screen first, back to the login screen). The compositor, terminal,
# passwd and gum are stubs; the real screen is checked on hardware, the PAM side in the lab (e2e-offline.sh,
# e2e-entra.sh).
source "$(dirname "$0")/lib.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export MONARCHY_IDENTITY_MARKS="$T/marks"   # honoured only when not root
HELPER=(python3 -I "$REPO/lib/password-expired")
mkdir -p "$T/marks"

echo "[the helper's marks]"
"${HELPER[@]}" pending dave; [[ $? == 1 ]] && ok "no mark: not pending" || bad "pending without a mark"
touch "$T/marks/dave"; "${HELPER[@]}" pending dave && ok "a fresh mark: pending" || bad "fresh mark not seen"
PAM_TYPE=account PAM_USER=dave "${HELPER[@]}" && ok "account phase: success for the marked sign-in" || bad "account phase"
touch -d '-10 min' "$T/marks/dave"; ! "${HELPER[@]}" pending dave && ok "an old mark counts for nothing" || bad "stale mark honoured"
! PAM_TYPE=account PAM_USER=erin "${HELPER[@]}" && ok "account phase: anyone unmarked falls through to the normal checks" || bad "unmarked account"
touch "$T/marks/x"; ! "${HELPER[@]}" pending ../marks/x && ! PAM_TYPE=account PAM_USER=../marks/x "${HELPER[@]}" && ok "a user name with a path in it is refused" || bad "path in user name"
! printf 'pw\0' | PAM_TYPE=auth PAM_USER=dave "${HELPER[@]}" && ok "auth phase refuses to run without root" || bad "auth phase ran unprivileged"

echo "[the second-step helper's marks]"
S2=(python3 -I "$REPO/lib/second-step"); M=$T/marks
echo pending > "$M/erin"; "${S2[@]}" pending erin && PAM_TYPE=account PAM_USER=erin "${S2[@]}" \
  && ok "a fresh pending mark: pending, and the account phase lets that sign-in through" || bad "pending mark"
echo refused > "$M/erin"; ! "${S2[@]}" pending erin && ! PAM_TYPE=account PAM_USER=erin "${S2[@]}" && ok "a refused sign-in is not pending" || bad "refused counted as pending"
echo pending > "$M/erin"; touch -d '-10 min' "$M/erin"; ! "${S2[@]}" pending erin && ok "an old mark counts for nothing" || bad "stale mark honoured"
! PAM_TYPE=account PAM_USER=frank "${S2[@]}" && ok "account phase: anyone unmarked falls through to the normal checks" || bad "unmarked account"
! "${S2[@]}" pending ../marks/erin && ! PAM_TYPE=account PAM_USER=../marks/erin "${S2[@]}" && ok "a user name with a path in it is refused" || bad "path in user name"
! printf 'pw\0' | PAM_TYPE=auth PAM_USER=erin "${S2[@]}" && ! PAM_TYPE=auth PAM_USER=erin "${S2[@]}" refused \
  && ok "auth phase refuses to run without root" || bad "auth phase ran unprivileged"

echo "[the session command]"
L=$T/lib B=$T/bin; mkdir -p "$L" "$B"; cp "$REPO/lib/sddm-session" "$L/"
printf '#!/bin/sh\n[ -e "%s/pending" ]\n' "$T" > "$L/password-expired"
printf '#!/bin/sh\n[ "$1" = verify ] && exit "$(cat %s/verify-rc)"\n[ -e "%s/second-pending" ]\n' "$T" "$T" > "$L/second-step"
printf '#!/bin/sh\necho "$*" > "%s/stock"\n' "$T" > "$T/stock-session"
printf '#!/bin/sh\n[ -e "%s/no-compositor" ] && exit 1\necho run >> "%s/kiosk"; bash -c "$OI_FORM"\n' "$T" "$T" > "$B/start-hyprland"
printf '#!/bin/sh\nexit "$(cat %s/passwd-rc)"\n' "$T" > "$B/passwd"
printf '#!/bin/sh\n[ "$1" = confirm ] && exit 1\nexit 0\n' > "$B/gum"   # "Back to sign-in"
printf '#!/bin/sh\n' > "$B/clear"; printf '#!/bin/sh\n' > "$B/sleep"
chmod +x "$L"/* "$T/stock-session" "$B"/*
session() { rm -f "$T/stock" "$T/kiosk"; PATH="$B:$PATH" USER=dave MONARCHY_IDENTITY_SDDM_SESSION="$T/stock-session" "$L/sddm-session" "$@" >/dev/null 2>&1; }
session uwsm start hyprland.desktop
[[ $? == 0 && ! -e $T/kiosk && $(cat "$T/stock" 2>/dev/null) == "uwsm start hyprland.desktop" ]] && ok "not pending: straight to SDDM's own session script, same arguments" || bad "not pending"
touch "$T/pending"; echo 0 > "$T/passwd-rc"; session uwsm start x
[[ -e $T/kiosk && $(cat "$T/stock" 2>/dev/null) == "uwsm start x" ]] && ok "pending, password changed: the change screen, then the desktop" || bad "changed"
echo 1 > "$T/passwd-rc"; session uwsm start x
[[ $? == 0 && -e $T/kiosk && ! -e $T/stock ]] && ok "pending, not changed, 'Back to sign-in': no desktop, ends like a logout (exit 0)" || bad "not changed"
touch "$T/no-compositor"; echo 0 > "$T/passwd-rc"; session uwsm start x
[[ $? == 0 && ! -e $T/stock ]] && ok "pending, the change screen can't start: no desktop" || bad "no compositor"
rm -f "$T/no-compositor" "$T/pending"; touch "$T/second-pending"; echo 0 > "$T/verify-rc"; session uwsm start x
[[ -e $T/kiosk && $(cat "$T/stock" 2>/dev/null) == "uwsm start x" ]] && ok "second step pending, done: that screen, then the desktop" || bad "second step done"
echo 1 > "$T/verify-rc"; session uwsm start x
[[ $? == 0 && -e $T/kiosk && ! -e $T/stock ]] && ok "second step pending, not done, 'Back to sign-in': no desktop, ends like a logout" || bad "second step not done"
rm -f "$T/second-pending"; touch "$T/pending"; printf '#!/bin/sh\necho "$*" > "%s/xstock"\n' "$T" > "$T/xsession"; chmod +x "$T/xsession"
xsession() { rm -f "$T/xstock" "$T/kiosk"; PATH="$B:$PATH" USER=dave XDG_SESSION_TYPE=x11 MONARCHY_IDENTITY_SDDM_XSESSION="$T/xsession" "$L/sddm-session" "$@" >/dev/null 2>&1; }
xsession openbox; [[ $? == 0 && ! -e $T/kiosk && ! -e $T/xstock ]] && ok "X11, pending: back to the login screen (no change screen there)" || bad "x11 pending"
rm -f "$T/pending"; xsession openbox; [[ $(cat "$T/xstock" 2>/dev/null) == openbox ]] && ok "X11, not pending: SDDM's own Xsession" || bad "x11 not pending"

echo "[the change screen's terminal is the only way out]"
foot=$(sed -n 's/^local FOOT = "\(.*\) "$/\1/p' "$REPO/lib/password-change.lua")
[[ $foot == *" --config=/dev/null "* && $foot == *"spawn-terminal=none"* && $foot == *"show-urls-launch=none"* ]] \
  && ok "foot ignores the person's config and can't start a shell or a URL opener" || bad "foot command: ${foot:-<not found>}"
! command -v foot >/dev/null || $foot --check-config 2>/dev/null && ok "foot accepts those options (when installed)" || bad "foot rejects: $foot"
result
