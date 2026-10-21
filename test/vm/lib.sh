# Shared helpers for the e2e suites. Source it from a suite in test/vm/: `source "$(dirname "$0")/lib.sh"`.
# Needs the lab (test/lab-check.sh). Every suite ends with `result`, which prints RESULT: ALL PASS or RESULT: FAIL.
set -u
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$H"
source ./ssh.sh
V=(ssh "${SSHO[@]}" -p 2222 tester@127.0.0.1)
PW='Passw0rd!Test'
LAB="ad --realm CORP.TEST --server dc.corp.test --admin Administrator"
fail=0

ok()  { printf '  PASS %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }
check() { local desc=$1; shift; if "$@"; then ok "$desc"; else bad "$desc"; fi; }   # check DESC CMD...
result() { ((fail)) && { echo "RESULT: FAIL"; exit 1; }; echo "RESULT: ALL PASS"; }

q() { local o="" a; for a in "$@"; do o+=" $(printf '%q' "$a")"; done; printf '%s' "$o"; }   # quote for the remote shell
cli()  { "${V[@]}" "~/oi/bin/monarchy-identity$(q "$@")" 2>&1; }                              # as tester
scli() { "${V[@]}" "sudo ~/oi/bin/monarchy-identity$(q "$@")" 2>&1; }                         # as root
st() { "${V[@]}" '~/oi/bin/monarchy-identity status --json'; }
dc() { docker exec oi-test-dc samba-tool "$@" 2>&1; }
has_account() { dc computer list | grep -qxF "$1"; }   # -F: the $ of a computer name is not a regex anchor

# pt [--session] SERVICE USER PASSWORD [--chauthtok NEW]: runs the real PAM stack in the VM; prints ALLOWED/DENIED/...
pt() { "${V[@]}" "sudo timeout 120 python3 -I /tmp/pamtest.py$(q "$@")" 2>&1; }
expect() { local want=$1 desc=$2 out; shift 2; out=$(pt "$@"); [[ $out == "$want"* ]] && ok "$desc" || bad "$desc (got: ${out:-<nothing>})"; }
# admin_prompt IDENTITY PASSWORD: answer a real polkit admin prompt as IDENTITY ("-": the first offered), asked by tester;
# prints AUTHORIZED/REFUSED/NOT-OFFERED and the identity
admin_prompt() { "${V[@]}" "python3 -I /tmp/adminprompt.py$(q "$@")" 2>&1; }
reset_locks() { "${V[@]}" 'for u in alice bob carol dave tester; do sudo faillock --user $u --reset 2>/dev/null; done; true'; }
pam_stock() { local f; for f in system-auth omarchy-lock-password sddm; do "${V[@]}" "cat /etc/pam.d/$f" | diff -q - "fixtures/pam.d/$f" >/dev/null || return 1; done; }

# enroll [extra args]: enroll with the lab directory (password on stdin); prints the output. Faillock is reset after,
# because before enrollment directory users don't resolve and the reset is a silent no-op.
enroll() { local out; out=$(echo "$PW" | "${V[@]}" "sudo ~/oi/bin/monarchy-identity enroll$(q $LAB "$@")" 2>&1); reset_locks; printf '%s' "$out"; }
enroll_ok() { local out; out=$(enroll "$@"); [[ $out == *"enrolled in"* ]] && ok "enroll $*" || { bad "enroll $*"; sed 's/^/      /' <<<"$out"; }; }
leave() { # whatever the laptop is enrolled with (--admin is the ad provider's)
  echo "$PW" | "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave --admin Administrator' >/dev/null 2>&1 \
    || "${V[@]}" 'sudo ~/oi/bin/monarchy-identity leave' >/dev/null 2>&1
}

# --- Entra ID: a real test tenant, opt-in (docs/dev/testing.md) ---
# entra_lab: load the tenant's details from $ENTRA_LAB_ENV, or say why not and return 1 (the suite or section skips)
entra_lab() {
  [[ -n ${ENTRA_LAB_ENV:-} && -r ${ENTRA_LAB_ENV:-} ]] || { echo "SKIP: no Entra test tenant (set ENTRA_LAB_ENV; see docs/dev/testing.md)"; return 1; }
  source "$ENTRA_LAB_ENV"
  local v; for v in ENTRA_TENANT ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET ENTRA_ALICE ENTRA_ALICE_PASSWORD ENTRA_BOB ENTRA_BOB_PASSWORD ENTRA_CAROL ENTRA_CAROL_PASSWORD; do
    [[ -n ${!v:-} ]] || { echo "SKIP: $ENTRA_LAB_ENV has no $v"; return 1; }
  done
}
# totp SECRET: the authenticator code for SECRET now, with at least 8 s of its 30 s left (an MFA test user's codes)
totp() {
  python3 -I - "$1" <<'PY'
import base64, hmac, struct, sys, time
t = int(time.time())
if 30 - t % 30 < 8:
    time.sleep(30 - t % 30); t = int(time.time())
s = sys.argv[1].upper().replace(" ", ""); h = hmac.new(base64.b32decode(s + "=" * (-len(s) % 8)), struct.pack(">Q", t // 30), "sha1").digest()
print("%06d" % ((struct.unpack(">I", h[(o := h[-1] & 15):o + 4])[0] & 0x7fffffff) % 10**6))
PY
}
# entra_codes [off]: ask Entra for an authenticator code rather than a push (Microsoft's system-preferred MFA picks the
# push whenever the user has one registered), so an MFA user's sign-in runs unattended. A test-only drop-in.
HB_TEST_CONF=/etc/himmelblau/himmelblau.conf.d/90-oi-test.conf
entra_codes() {
  if [[ ${1:-} == off ]]; then "${V[@]}" "sudo rm -f $HB_TEST_CONF"; return; fi
  "${V[@]}" "sudo install -d ${HB_TEST_CONF%/*} && printf '[global]\nmfa_method = PhoneAppOTP\n' | sudo tee $HB_TEST_CONF >/dev/null"
}
# himmelblau_install: the newest himmelblau package in test/vm/images/ in the VM, unless it's already there (a suite
# may have removed it, or the lab has a newer build)
himmelblau_install() {
  local p; p=$(ls images/himmelblau-*.pkg.tar.zst 2>/dev/null | sort -V | tail -1)
  [[ -n $p ]] || { bad "no himmelblau package in test/vm/images/ (build it: himmelblau/build.sh)"; return 1; }
  local want; want=$(basename "$p" | sed -E 's/^himmelblau-(.*)-[^-]+\.pkg\.tar\.zst$/\1/')
  [[ $("${V[@]}" 'pacman -Q himmelblau 2>/dev/null' | cut -d' ' -f2) == "$want" ]] && return
  scp -q "${SSHO[@]}" -P 2222 "$p" tester@127.0.0.1:/home/tester/himmelblau.pkg.tar.zst \
    && "${V[@]}" 'sudo pacman -U --noconfirm ~/himmelblau.pkg.tar.zst' >/dev/null 2>&1
}
# hb_mark: where himmelblaud's log is now; hb_log MARK: its log since; steps MARK: how many sign-in steps since (each
# one went to Entra). By journal cursor: the lab's clock jumps (e2e-offline), and a time would catch the previous check's steps.
hb_mark() { "${V[@]}" 'sudo journalctl -u himmelblaud -n0 --show-cursor -q' | sed -n 's/^-- cursor: //p'; }
hb_log() { "${V[@]}" "sudo journalctl -u himmelblaud --after-cursor=$(printf %q "$1") --no-pager -o cat"; }
steps() { hb_log "$1" | grep -c 'pam authenticate step'; }
# Every Entra run registers the VM again; delete the device objects it leaves (needs az signed in to the tenant).
# Entra's list can lag a registration by a minute, so a cleanup at exit may miss the last device; the next run's gets it.
entra_devices_cleanup() {
  command -v az >/dev/null || { echo "  NOTE: delete the device 'oi-client' in the Entra admin center"; return; }
  local id; for id in $(az rest --method get --url "https://graph.microsoft.com/v1.0/devices?\$filter=displayName eq 'oi-client'&\$select=id" --query 'value[].id' -o tsv 2>/dev/null); do
    az rest --method delete --url "https://graph.microsoft.com/v1.0/devices/$id" >/dev/null 2>&1; done
}

# fresh: push the repo, reset PAM/SDDM to stock Omarchy, make sure the machine isn't enrolled.
fresh() {
  ./deploy.sh --fixtures >/dev/null
  scp -q "${SSHO[@]}" -P 2222 pamtest.py adminprompt.py tester@127.0.0.1:/home/tester/ \
    && "${V[@]}" 'sudo install -m 644 ~/pamtest.py ~/adminprompt.py /tmp/'
  leave
}
