#!/bin/bash
# An expired password at the login screen: the helper's marks, and the session command's choices (desktop, change
# screen first, back to the login screen). The compositor, terminal, passwd and gum are stubs; the real screen is
# checked on hardware, the PAM side in the lab (e2e-offline.sh).
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

echo "[the login-steps helper]"
LS=(python3 -I "$REPO/lib/login-steps")
! printf 'pw\0' | PAM_TYPE=auth PAM_USER=dave "${LS[@]}" && ! PAM_TYPE=auth PAM_USER=dave "${LS[@]}" refused \
  && ok "refuses to run without root (it signs people in)" || bad "login-steps ran unprivileged"
# Its conversation with the module, against scripts of what pam_himmelblau 4.0.6 asks (P a prompt, T a message, W
# seconds the module takes, rc its result): the outcome, what it answered, and what reaches the login screen.
steps() { python3 -I - "$REPO/lib/login-steps" "$@" <<'PY'
import importlib.machinery, importlib.util, io, contextlib, sys, time
loader = importlib.machinery.SourceFileLoader("login_steps", sys.argv[1])
ls = importlib.util.module_from_spec(importlib.util.spec_from_loader("login_steps", loader)); loader.exec_module(ls)
ls.WAITING = 0.1
code, new, script = sys.argv[2], sys.argv[3], sys.argv[4:]
sent, calls = [], [0]
def sign_in(user, answer):
    calls[0] += 1; n = 0
    for step in script:
        kind, _, text = step.partition(" ")
        if kind == "rc":
            return int(text)
        if kind == "W":
            time.sleep(float(text)); continue
        reply = answer(n, 1 if kind == "P" else 4, text)
        if kind == "P":
            n += 1
            if reply is None:
                return ls.PAM_CONV_ERR
            sent.append(reply)
    return 0
ls.sign_in = sign_in
out = io.StringIO()
with contextlib.redirect_stdout(out):
    r = ls.once("dave", "old-pw", code, new)
print(r, "|", ",".join(sent), "|", calls[0], "|", out.getvalue().strip().replace("\n", " / "))
PY
}
BANNER="T Update your password
You need to update your password because this is
the first time you are signing in, or because your
password has expired."
BANNER1="Update your password You need to update your password because this is the first time you are signing in, or because your password has expired."
CHANGE=("P Password: " "$BANNER" "P New password: " "$BANNER" "P Confirm password: " "T Changing the password. Please wait...")
r=$(steps "" "" "P Password: "); [[ $r == "ok | old-pw | 1 | " ]] && ok "a password alone: signed in" || bad "password: $r"
r=$(steps "" "" "P Password: " "P Password: "); [[ $r == "refused | old-pw | 1 | " ]] && ok "the password asked again: refused, sent once" || bad "wrong password: $r"
W="T AADSTS50126: Error validating credentials due to invalid username or password. Trace ID: 1f Correlation ID: b6 Timestamp: 2026-10-21 15:32:45Z"
r=$(steps "" "" "P Password: " "$W" "T Use the password for your Office 365 or Microsoft online login." "P Password: ")
[[ $r == "refused | old-pw | 1 | Error validating credentials due to invalid username or password. / monarchy-identity: refused" ]] \
  && ok "a wrong password: Entra's sentence alone (no code, IDs or time), then 'refused'" || bad "wrong password, why: $r"
S="T UserInformationNotProvided - Session information isn't sufficient for single-sign-on. This means that a user isn't signed in."
r=$(steps "" "" "P Password: " "$S" "P Password: ")
[[ $r == "refused | old-pw | 1 | Microsoft needs you to sign in on the web first, "*"myaccount.microsoft.com"*" / monarchy-identity: refused" ]] \
  && ok "Entra wants a web sign-in first (a password to change on a joined laptop): says where, not Entra's text" || bad "web first: $r"
r=$(steps 000000 "" "P Password: " "T Enter the code" "P Code: " "T AADSTS50126: The code is wrong." "P Code: ")
[[ $r == "refused | old-pw,000000 | 1 | The code is wrong. / monarchy-identity: refused" ]] \
  && ok "a wrong code: why, then 'refused'" || bad "wrong code, why: $r"
r=$(steps 000000 "" "P Password: " "T Enter the code" "P Code: " "T Authentication failed." "W 0.3" "P Code: ")
[[ $r == "refused | old-pw,000000 | 1 | Authentication failed. / monarchy-identity: refused" ]] \
  && ok "  ... said once when it stood while the module worked" || bad "wrong code, why said twice: $r"
r=$(steps "" "" "P Password: " "T Enter the code" "P Code: "); [[ $r == "code | old-pw | 1 | Enter the code / monarchy-identity: code wanted" ]] \
  && ok "a code wanted: its message and 'code wanted', nothing sent for it" || bad "code: $r"
r=$(steps "" "" "P Password: " "$BANNER" "P New password: ")
[[ $r == "new | old-pw | 1 | $BANNER1 / monarchy-identity: new password wanted" ]] \
  && ok "must be changed: the directory's message and 'new password wanted', nothing sent as a new password" || bad "new wanted: $r"
r=$(steps "" "new-pw-123" "${CHANGE[@]}"); [[ $r == "ok | old-pw,new-pw-123,new-pw-123 | 1 | " ]] \
  && ok "must be changed, a new password given: the new one twice, signed in" || bad "changed: $r"
r=$(steps "" "new-pw-123" "${CHANGE[@]}" "T Enter the code" "P Code: ")
[[ $r == "code | old-pw,new-pw-123,new-pw-123 | 1 | monarchy-identity: password changed / Enter the code / monarchy-identity: code wanted" ]] \
  && ok "changed, then a code wanted: says the password changed, then asks for the code" || bad "changed then code: $r"
r=$(steps 123456 "new-pw-123" "${CHANGE[@]}" "T Enter the code" "P Code: "); [[ $r == "ok | old-pw,new-pw-123,new-pw-123,123456 | 1 | monarchy-identity: password changed" ]] \
  && ok "changed and the code given: signed in" || bad "changed with code: $r"
r=$(steps 123456 "new-pw-123" "P Password: " "T Enter the code" "P Code: " "${CHANGE[@]:1}" "T Enter the code" "P Code: ")
[[ $r == "code | old-pw,123456,new-pw-123,new-pw-123 | 1 | monarchy-identity: password changed / Enter the code / monarchy-identity: code wanted" ]] \
  && ok "MFA: the code, the change, then a code again: the spent code isn't sent twice, a fresh one is wanted" || bad "code, change, code: $r"
r=$(steps "" "short" "P Password: " "$BANNER" "P New password: " "T Chosen password is too short! 8 chars required." "$BANNER" "P New password: ")
[[ $r == "refused | old-pw,short | 1 | Chosen password is too short! 8 chars required." ]] \
  && ok "a new password the module won't take: why, and refused (never sent again)" || bad "too short: $r"
r=$(steps "" "new-pw-123" "${CHANGE[@]}" "T Failed to change user password: it was used before" "P New password: ")
[[ $r == "refused | old-pw,new-pw-123,new-pw-123 | 1 | Failed to change user password: it was used before" ]] \
  && ok "a new password Entra won't take: its reason, and refused" || bad "Entra refuses: $r"
r=$(steps "" "new-pw-123" "${CHANGE[@]}" "rc 26"); [[ $r == "None | old-pw,new-pw-123,new-pw-123 | 1 | " ]] \
  && ok "aborted after the new password was sent: not tried again with the old one" || bad "abort after change: $r"
r=$(steps "" "" "rc 26"); [[ $(cut -d'|' -f3 <<<"$r") == " 2 " ]] && ok "aborted before anything was sent: asked once more (the offline cache)" || bad "abort: $r"

echo "[the session command]"
L=$T/lib B=$T/bin; mkdir -p "$L" "$B"; cp "$REPO/lib/sddm-session" "$L/"
printf '#!/bin/sh\n[ -e "%s/pending" ]\n' "$T" > "$L/password-expired"
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
rm -f "$T/no-compositor"; printf '#!/bin/sh\necho "$*" > "%s/xstock"\n' "$T" > "$T/xsession"; chmod +x "$T/xsession"
xsession() { rm -f "$T/xstock" "$T/kiosk"; PATH="$B:$PATH" USER=dave XDG_SESSION_TYPE=x11 MONARCHY_IDENTITY_SDDM_XSESSION="$T/xsession" "$L/sddm-session" "$@" >/dev/null 2>&1; }
xsession openbox; [[ $? == 0 && ! -e $T/kiosk && ! -e $T/xstock ]] && ok "X11, pending: back to the login screen (no change screen there)" || bad "x11 pending"
rm -f "$T/pending"; xsession openbox; [[ $(cat "$T/xstock" 2>/dev/null) == openbox ]] && ok "X11, not pending: SDDM's own Xsession" || bad "x11 not pending"

echo "[the change screen's terminal is the only way out]"
foot=$(sed -n 's/^local FOOT = "\(.*\) "$/\1/p' "$REPO/lib/password-change.lua")
[[ $foot == *" --config=/dev/null "* && $foot == *"spawn-terminal=none"* && $foot == *"show-urls-launch=none"* ]] \
  && ok "foot ignores the person's config and can't start a shell or a URL opener" || bad "foot command: ${foot:-<not found>}"
! command -v foot >/dev/null || $foot --check-config 2>/dev/null && ok "foot accepts those options (when installed)" || bad "foot rejects: $foot"
result
