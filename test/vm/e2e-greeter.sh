#!/bin/bash
# Real SDDM greeter test: type credentials with QEMU sendkey into the actual greeter (X11 greeter, our
# monarchy-identity theme, real PAM stack) and check that sessions start / don't start. Needs DC + VM
# (started by run.sh with its monitor socket). Screenshots land in $SHOTS (default: a temp dir, printed).
source "$(dirname "$0")/lib.sh"
SHOTS=${SHOTS:-$(mktemp -d)}; echo "screenshots: $SHOTS"
shot() { ./qmon.py shot "$SHOTS/$1.png" 2>/dev/null; }
sessions() { "${V[@]}" 'sudo wc -l < /run/oi-test/session.log 2>/dev/null || echo 0'; }
last_user() { "${V[@]}" 'sudo tail -1 /run/oi-test/session.log 2>/dev/null | cut -d" " -f1'; }
greeter_up() { "${V[@]}" 'sudo journalctl -u sddm --no-pager -o cat | grep -c "Greeter session started successfully"'; }
logout_graphical() { # end the test session normally (it exits when /run/oi-test/logout exists) and wait for the greeter
  local n; n=$(greeter_up)
  "${V[@]}" 'sudo touch /run/oi-test/logout'
  for _ in $(seq 40); do sleep 1; [[ $(greeter_up) -gt $n ]] && break; done
  "${V[@]}" 'sudo rm -f /run/oi-test/logout'; sleep 4
}
# login <label> <username|-> <password> <backtab 0|1>
#   username "-"  : keep the prefilled username; type only the password (focus is already on it)
#   backtab 1     : focus is on the password box (prefilled last user, or after a failure): Shift+Tab to the
#                   username box first. A pristine greeter (no last user) already has focus on the username.
# Waits up to 25s for a NEW session line; returns 0 if one appeared.
login() {
  local before; before=$(sessions)
  if [[ $2 != - ]]; then
    [[ ${4:-0} == 1 ]] && { ./qmon.py key shift-tab; sleep 1; }
    ./qmon.py key ctrl-a; ./qmon.py type "$2"; ./qmon.py key ret; sleep 1
  fi
  ./qmon.py type "$3"; shot "$1-typed"; ./qmon.py key ret
  for _ in $(seq 25); do sleep 1; [[ $(sessions) -gt $before ]] && return 0; done
  return 1
}

diag() { # print what SDDM and the session log say (called when a login step fails)
  echo "      --- session log:"; "${V[@]}" 'sudo cat /run/oi-test/session.log 2>&1 | tail -4' | sed 's/^/      /'
  echo "      --- sddm:"; "${V[@]}" 'sudo journalctl -u sddm --no-pager -o cat | grep -E "Authentication|Auth:|Login|Session started|crashed|successful|Greeter" | tail -7 | cut -c1-140' | sed 's/^/      /'
}
echo "[setup: packaged install, enroll, X11 greeter for the VM]"
./deploy.sh --fixtures >/dev/null
./install-package.sh >/dev/null
tar -C fixtures -czf - omarchy-theme-assets oi-test-session oi-test.desktop | "${V[@]}" 'cd /tmp && rm -rf oi-fx && mkdir oi-fx && tar -xzf - -C oi-fx && sudo install -d /usr/share/sddm/themes/omarchy /usr/share/xsessions && sudo install -m644 oi-fx/omarchy-theme-assets/*.png /usr/share/sddm/themes/omarchy/ && sudo install -m755 oi-fx/oi-test-session /usr/local/bin/oi-test-session && sudo install -m644 oi-fx/oi-test.desktop /usr/share/xsessions/oi-test.desktop'
"${V[@]}" 'sudo rm -rf /run/oi-test; sudo install -d -m 0777 /run/oi-test; sudo install -m 0666 /dev/null /run/oi-test/session.log'
echo "$PW" | "${V[@]}" 'sudo systemctl stop sddm; sudo /usr/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
"${V[@]}" 'sudo rm -rf /home/alice /home/bob /home/carol /home/dave /run/oi-test/logout; for u in alice bob carol tester; do sudo faillock --user $u --reset 2>/dev/null; done'
last_session() { "${V[@]}" "printf '[Last]\nSession=%s\n' $1 | sudo tee /var/lib/sddm/state.conf >/dev/null"; }   # no last user
last_session /usr/share/xsessions/oi-test.desktop   # the VM also has Hyprland's sessions (the package needs Hyprland)
out=$(echo "$PW" | "${V[@]}" "sudo /usr/bin/monarchy-identity enroll$(q $LAB --groups oi-laptop-users)" 2>&1)
[[ $out == *"enrolled in"* ]] && ok enroll || { bad enroll; echo "$out" | sed 's/^/      /'; }
"${V[@]}" 'printf "[General]\nDisplayServer=x11\n" | sudo tee /etc/sddm.conf.d/zz-vm-x11.conf >/dev/null; sudo systemctl start sddm'
for _ in $(seq 40); do sleep 1; [[ $("${V[@]}" 'sudo journalctl -u sddm --no-pager -o cat | grep -c "Greeter session started successfully"') -ge 1 ]] && break; done; sleep 4
shot 0-greeter
"${V[@]}" 'sudo journalctl -u sddm --no-pager -o cat | grep -q "monarchy-identity"' && ok "greeter loaded the monarchy-identity theme" || bad "greeter did not load our theme"

echo "[directory user, allowed group]"
login alice alice "$PW" 0 && [[ $(last_user) == alice ]] && ok "alice typed username+password at the greeter -> session started as alice" || bad "alice got no session"
"${V[@]}" 'sudo stat -c "%U %a" /home/alice' | grep -qx "alice 700" && ok "alice's home created (0700) by the greeter login" || bad "alice home"
"${V[@]}" 'loginctl list-sessions --no-legend | awk "\$4==\"seat0\" && \$3==\"alice\"" | grep -q .' && ok "loginctl: alice has a seat0 session" || bad "no seat0 session for alice"
logout_graphical; shot 1-after-logout
echo "[remember last user: username is prefilled, only the password is needed]"
login 1b - "$PW" && [[ $(last_user) == alice ]] && ok "second login: only the password typed (username prefilled with alice)" || bad "prefilled-username login failed"
logout_graphical

echo "[denied user: right password, but not in the allowed group]"
login 2-carol carol "$PW" 1 && bad "carol (not in oi-laptop-users) got a session!" || ok "carol: no session started"
"${V[@]}" 'test ! -e /home/carol' && ok "carol got no home directory" || bad "carol home exists"
shot 2-carol-failed

echo "[recover on the same screen: switch to another user after a failure]"
"${V[@]}" 'sudo faillock --user bob --reset' 2>/dev/null
login 3-bob bob "$PW" 1 && [[ $(last_user) == bob ]] && ok "after a failed attempt, retyped username (bob) and logged in" || { bad "could not switch user after failure"; diag; }
logout_graphical

echo "[wrong password]"
login 4-wrong alice "wrong-password" 1 && bad "wrong password started a session" || ok "alice + wrong password: no session"
"${V[@]}" 'sudo faillock --user alice --reset' 2>/dev/null

echo "[local break-glass user at the greeter]"
login 5-tester tester tester 1 && [[ $(last_user) == tester ]] && ok "local user 'tester' can log in at the greeter" || { bad "local user could not log in"; diag; }
logout_graphical

echo "[expired password: let through and marked by the real SDDM, but an X11 session can't show the change screen]"
dc user delete dave >/dev/null; dc user create dave "$PW" --must-change-at-next-login >/dev/null; dc group addmembers oi-laptop-users dave >/dev/null
n=$(greeter_up)
login 6-dave dave "$PW" 1 && bad "dave got a session without changing the password" || ok "dave (expired): no session"
"${V[@]}" 'sudo test -e /run/monarchy-identity/password-change/dave' && ok "  ... but past the password check and marked (the guard saw this SDDM start after enroll)" || { bad "dave not marked"; diag; }
for _ in $(seq 30); do sleep 1; [[ $(greeter_up) -gt $n ]] && break; done; sleep 3; shot 6-dave-back
[[ $(greeter_up) -gt $n ]] && ok "  ... and the login screen is back" || bad "greeter did not come back"
"${V[@]}" 'sudo faillock --user bob --reset' 2>/dev/null
login 7-bob bob "$PW" 1 && [[ $(last_user) == bob ]] && ok "the next person signs in normally" || { bad "sign-in after the expired user failed"; diag; }
logout_graphical

echo "[expired password, Hyprland session: the change-password screen, then the desktop]"
NEW='D4ve-New-Pw!'
dave_has() { "${V[@]}" "pgrep -u dave -a $1" 2>/dev/null; }
wait_for() { local i; for i in $(seq "$1"); do sleep 1; eval "$2" && return 0; done; return 1; }
greeter_restart() { local n; n=$(greeter_up); "${V[@]}" 'sudo systemctl restart sddm'; wait_for 40 '[[ $(greeter_up) -gt $n ]]'; sleep 4; }
last_session /usr/share/wayland-sessions/hyprland.desktop; greeter_restart
./qmon.py type dave; ./qmon.py key ret; sleep 1; ./qmon.py type "$PW"; ./qmon.py key ret
wait_for 60 'dave_has foot >/dev/null' && ok "dave (expired) signs in: the change-password screen opens" || { bad "no change-password screen"; diag; }
sleep 3; shot 8-change-password
./qmon.py type wrong-password; ./qmon.py key ret; sleep 8; shot 8b-wrong-current
n=$(greeter_up); ./qmon.py key n
wait_for 40 '[[ $(greeter_up) -gt $n ]]' && ! dave_has Hyprland >/dev/null && ok "  wrong current password, 'Back to sign-in': the login screen, no desktop" || { bad "back to sign-in"; shot 8c-stuck; diag; }
"${V[@]}" 'sudo faillock --user dave --reset' 2>/dev/null
# The login screen now remembers dave with focus on the password; start it as for the first sign-in instead, so what is
# typed lands where it's meant to (a retry typed while a refusal is in flight gets cleared by it).
last_session /usr/share/wayland-sessions/hyprland.desktop; greeter_restart
./qmon.py type dave; ./qmon.py key ret; sleep 1; ./qmon.py type "$PW"; ./qmon.py key ret
wait_for 60 'dave_has foot >/dev/null' && ok "  signs in again: the screen again" || { bad "no change-password screen the second time"; shot 8d; diag; }
sleep 3; ./qmon.py type "$PW"; ./qmon.py key ret; sleep 3; ./qmon.py type "$NEW"; ./qmon.py key ret; sleep 2; ./qmon.py type "$NEW"; ./qmon.py key ret
sleep 3; shot 9-changed
wait_for 60 '! dave_has foot >/dev/null && dave_has Hyprland | grep -vq password-change.lua' && ok "  password changed: dave's desktop starts" || { bad "no desktop after the change"; shot 9b; diag; }
! dave_has Hyprland | grep -q password-change.lua && ok "  ... and the change screen is gone" || bad "change screen still running"
expect ALLOWED "the directory has the new password" system-auth dave "$NEW"
n=$(greeter_up); "${V[@]}" 'sudo loginctl terminate-user dave'; wait_for 40 '[[ $(greeter_up) -gt $n ]]'
last_session /usr/share/xsessions/oi-test.desktop
dc user delete dave >/dev/null

# Entra (opt-in, a real tenant): the real SDDM answers every prompt with the typed password, so this is where the
# login screen's asking once shows, and where an MFA user types the code into the theme's code line.
echo "[Entra ID: the login screen asks once; an MFA user's code there]"
if entra_lab && [[ -n ${ENTRA_DAVE:-} && -n ${ENTRA_DAVE_PASSWORD:-} && -n ${ENTRA_DAVE_TOTP_SECRET:-} ]]; then
  SECRET=/root/entra-secret
  echo "$PW" | "${V[@]}" 'sudo /usr/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
  himmelblau_install; entra_devices_cleanup; entra_codes
  printf '%s\n' "$ENTRA_CLIENT_SECRET" | "${V[@]}" "sudo install -m 600 /dev/stdin $SECRET"
  out=$("${V[@]}" "sudo /usr/bin/monarchy-identity enroll entra --tenant $ENTRA_TENANT --client-id $ENTRA_CLIENT_ID --password-file $SECRET --groups linux-users" 2>&1)
  "${V[@]}" "sudo rm -f $SECRET"
  [[ $out == *"enrolled in $ENTRA_TENANT"* ]] && ok "enroll entra" || { bad "enroll entra"; sed 's/^/      /' <<<"$out"; }
  has() { "${V[@]}" "pgrep -u$(q "$1") -a $2" 2>/dev/null; }
  steps() { "${V[@]}" "sudo journalctl -u himmelblaud --since @$1 --no-pager -o cat | grep -c 'pam authenticate step'"; }
  last_session /usr/share/wayland-sessions/hyprland.desktop; greeter_restart   # a fresh greeter, nobody remembered
  since=$("${V[@]}" 'date +%s')
  ./qmon.py type "$ENTRA_BOB"; ./qmon.py key ret; sleep 1; ./qmon.py type "not-bobs-password-1"; ./qmon.py key ret
  sleep 15; n=$(steps "$since"); shot 10-entra-wrong
  [[ $n == 1 ]] && ! has "$ENTRA_BOB" Hyprland >/dev/null && ok "bob, wrong password: no session, and Entra was asked once" || { bad "wrong password sent $n times"; diag; }
  last_session /usr/share/wayland-sessions/hyprland.desktop; greeter_restart   # also ends a loop, if there was one
  since=$("${V[@]}" 'date +%s')
  ./qmon.py type "$ENTRA_DAVE"; ./qmon.py key ret; sleep 1; ./qmon.py type "$ENTRA_DAVE_PASSWORD"; ./qmon.py key ret
  sleep 10; shot 11-code-wanted
  n=$(steps "$since"); [[ $n == 1 ]] && ! has "$ENTRA_DAVE" Hyprland >/dev/null && ok "dave (MFA, first sign-in here): the password alone isn't enough, nothing sent as the code" || { bad "dave, password only: $n steps"; diag; }
  ./qmon.py type "$(totp "$ENTRA_DAVE_TOTP_SECRET")"; ./qmon.py key ret   # the theme put the focus on its code line
  wait_for 60 'has "$ENTRA_DAVE" Hyprland >/dev/null' && ok "  the code on the login screen: dave's desktop starts" || { bad "no desktop after the code"; shot 12-no-desktop; diag; }
  sleep 3; shot 12-desktop
  n=$(greeter_up); "${V[@]}" "sudo loginctl terminate-user $(q "$ENTRA_DAVE")"; wait_for 40 '[[ $(greeter_up) -gt $n ]]'
  "${V[@]}" 'sudo /usr/bin/monarchy-identity leave' >/dev/null 2>&1
  entra_codes off; entra_devices_cleanup
  last_session /usr/share/xsessions/oi-test.desktop
else
  echo "  SKIP: needs ENTRA_LAB_ENV with an MFA user (ENTRA_DAVE, ENTRA_DAVE_PASSWORD, ENTRA_DAVE_TOTP_SECRET)"
fi

"${V[@]}" 'sudo systemctl stop sddm; sudo rm -f /etc/sddm.conf.d/zz-vm-x11.conf' >/dev/null 2>&1
echo "$PW" | "${V[@]}" 'sudo /usr/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1
"${V[@]}" 'sudo pacman -R --noconfirm monarchy-identity' >/dev/null 2>&1   # leave the VM unpackaged, as other suites expect
result
