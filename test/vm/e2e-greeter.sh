#!/bin/bash
# Real SDDM greeter test: type credentials with QEMU sendkey into the actual greeter (X11 greeter, our
# omarchy-identity theme, real PAM stack) and check that sessions start / don't start. Needs DC + VM
# (started by run.sh with its monitor socket). Screenshots land in $SHOTS (default: a temp dir, printed).
set -u
H="$(cd "$(dirname "$0")" && pwd)"; cd "$H"
V=(ssh -i keys/id_oi -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'; fail=0
SHOTS=${SHOTS:-$(mktemp -d)}; echo "screenshots: $SHOTS"
ok() { printf '  PASS %s\n' "$1"; }; bad() { printf '  FAIL %s\n' "$1"; fail=1; }
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
echo "[setup: packaged install, enrol, X11 greeter for the VM]"
./deploy.sh --fixtures >/dev/null
./install-package.sh >/dev/null
tar -C fixtures -czf - omarchy-theme-assets oi-test-session oi-test.desktop | "${V[@]}" 'cd /tmp && rm -rf oi-fx && mkdir oi-fx && tar -xzf - -C oi-fx && sudo install -d /usr/share/sddm/themes/omarchy /usr/share/xsessions && sudo install -m644 oi-fx/omarchy-theme-assets/*.png /usr/share/sddm/themes/omarchy/ && sudo install -m755 oi-fx/oi-test-session /usr/local/bin/oi-test-session && sudo install -m644 oi-fx/oi-test.desktop /usr/share/xsessions/oi-test.desktop'
"${V[@]}" 'sudo rm -rf /run/oi-test; sudo install -d -m 0777 /run/oi-test; sudo install -m 0666 /dev/null /run/oi-test/session.log'
echo "$PW" | "${V[@]}" 'sudo systemctl stop sddm; sudo /usr/bin/omarchy-identity leave --admin Administrator' >/dev/null 2>&1
"${V[@]}" 'sudo rm -rf /home/alice /home/bob /home/carol /var/lib/sddm/state.conf /run/oi-test/logout; for u in alice bob carol tester; do sudo faillock --user $u --reset 2>/dev/null; done'
out=$(echo "$PW" | "${V[@]}" "sudo /usr/bin/omarchy-identity enroll sssd --realm CORP.TEST --server dc.corp.test --admin Administrator --mode groups --groups oi-laptop-users --disable-autologin" 2>&1)
[[ $out == *"enrolled in"* ]] && ok enrol || { bad enrol; echo "$out" | sed 's/^/      /'; }
"${V[@]}" 'printf "[General]\nDisplayServer=x11\n" | sudo tee /etc/sddm.conf.d/zz-vm-x11.conf >/dev/null; sudo systemctl start sddm'
for _ in $(seq 40); do sleep 1; [[ $("${V[@]}" 'sudo journalctl -u sddm --no-pager -o cat | grep -c "Greeter session started successfully"') -ge 1 ]] && break; done; sleep 4
shot 0-greeter
"${V[@]}" 'sudo journalctl -u sddm --no-pager -o cat | grep -q "omarchy-identity"' && ok "greeter loaded the omarchy-identity theme" || bad "greeter did not load our theme"

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

"${V[@]}" 'sudo systemctl stop sddm; sudo rm -f /etc/sddm.conf.d/zz-vm-x11.conf' >/dev/null 2>&1
echo "$PW" | "${V[@]}" 'sudo /usr/bin/omarchy-identity leave --admin Administrator' >/dev/null 2>&1
"${V[@]}" 'sudo pacman -R --noconfirm omarchy-identity' >/dev/null 2>&1   # leave the VM unpackaged, as other suites expect
((fail)) && { echo "RESULT: FAIL"; exit 1; } || echo "RESULT: ALL PASS"
