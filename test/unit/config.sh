#!/bin/bash
# The config reader/writer (lib/common.sh): hostile values round-trip, malformed files are refused with a line number,
# and the CLI stops on a malformed config.toml instead of reading defaults.
source "$(dirname "$0")/lib.sh"
sandbox
C=$MONARCHY_IDENTITY_CONF; mkdir -p "$(dirname "$C")"
lib() { local s=$1; shift; OUT=$(OI_ROOT=$REPO bash -c 'source "$OI_ROOT/lib/common.sh"; '"$s" _ "$@" 2>&1); RC=$?; }   # lib 'BASH' ARGS...

# round trip: what conf_write stores, kv_get gives back byte for byte
for v in 'plain' 'has "quotes"' 'a=b=c' 'back\slash' 'trailing\' '\n literally' $'two\nlines' $'tab\there' \
         '# not a comment' '  spaced  ' "it's" 'x = "injected"' $'ok\nprovider = "evil"' '$(id) `id` ;|&'; do
  lib 'conf_write provider=stub "k=$1"; conf_get k' "$v"
  [[ $RC -eq 0 && $OUT == "$v" ]] && ok "round trip $(printf %q "$v")" || bad "round trip $(printf %q "$v"): got $(printf %q "$OUT")"
  lib 'conf_get provider'
  [[ $OUT == stub && $(grep -c . "$C") -eq 2 ]] && ok "  and nothing else changed" || bad "  file: $(cat "$C")"
done
lib 'conf_write "k=$(printf "a\rb")"'
[[ $RC -ne 0 && $OUT == *"control characters"* ]] && ok "control characters refused on write" || bad "control characters: $OUT"
lib 'conf_write "bad key=v"'
[[ $RC -ne 0 && $OUT == *"invalid config key"* ]] && ok "bad key refused on write" || bad "bad key: $OUT"

# conf_set keeps the other keys, their order and their values
lib 'conf_write a=1 "b=x \"y\"" c=3; conf_set b=2 d=4; cat "$OI_CONF"'
[[ $OUT == $'a = "1"\nc = "3"\nb = "2"\nd = "4"' ]] && ok "conf_set changes some keys, keeps the rest" || bad "conf_set: $OUT"
lib 'conf_write $'"'"'a=x\ny'"'"' b=1; conf_set b=2; conf_get a'
[[ $OUT == $'x\ny' ]] && ok "conf_set keeps an escaped value intact" || bad "conf_set escaped: $(printf %q "$OUT")"

# what a person or an MDM may write: comments, blank lines, spacing, trailing comments, CRLF line ends
printf '# managed\n\n  provider="stub"   # inline\r\nlogin_mode =  "groups"\n\ttenant = "a\\"b"' > "$C"
lib 'echo "$(conf_get provider)|$(conf_get login_mode)|$(conf_get tenant)|$(conf_get missing dflt)"'
[[ $RC -eq 0 && $OUT == 'stub|groups|a"b|dflt' ]] && ok "comments, spacing, CRLF, no final newline" || bad "lenient forms: $OUT"
lib 'conf_check' ; [[ $RC -eq 0 ]] && ok "conf_check accepts it" || bad "conf_check: $OUT"
check "the providers' pam.conf parses" lib 'kv_get "$OI_ROOT/providers/ad/pam.conf" module'
check "the packaged default config parses" lib 'kv_get "$OI_ROOT/packaging/config.toml" provider'

# malformed: refused, and the message names the line
bad_file() { # bad_file LABEL CONTENT MESSAGE
  printf '%s\n' 'provider = "stub"' "$2" > "$C"
  lib 'conf_get provider'
  [[ $RC -ne 0 && $OUT == *"line 2"*"$3"* ]] && ok "refused: $1" || bad "$1: rc $RC, $OUT"
}
bad_file "unquoted value"       'login_mode = groups'         'not key = "value"'
bad_file "single quotes"        "login_mode = 'groups'"       'not key = "value"'
bad_file "unclosed quote"       'login_mode = "groups'        'not key = "value"'
bad_file "stray quote inside"   'login_mode = "gro"ups"'      'not key = "value"'
bad_file "two values"           'login_mode = "a" "b"'        'not key = "value"'
bad_file "no ="                 'login_mode "groups"'         'not key = "value"'
bad_file "key with a space"     'login mode = "groups"'       'not key = "value"'
bad_file "a section"            '[sssd]'                      'not key = "value"'
bad_file "unknown escape"       'login_mode = "a\qb"'         "unknown escape '\\q'"
bad_file "duplicate key"        'provider = "evil"'           "sets 'provider' a second time"

# the CLI stops on a malformed config.toml, before reading anything from it
printf 'provider = "local"\nlogin_mode = none\n' > "$C"
oi status; [[ $RC -ne 0 && $OUT == *"line 2"* ]] && ok "status refuses a malformed config" || bad "status: rc $RC, $OUT"
BEFORE=$(snap); oi policy set --groups oi-laptop-users; refused "policy set on a malformed config" "line 2"

result
