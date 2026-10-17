#!/bin/bash
# Unit tests for input validation (no VM, no root). Run: test/unit/validation.sh
cd "$(dirname "$0")/../.." || exit 1
export OI_ROOT=$PWD; source providers/ad/lib.sh
fail=0
t() { # t <should-pass 1|0> <fn> args...
  local want=$1 fn=$2; shift 2
  if "$fn" "$@" 2>/dev/null; then got=1; else got=0; fi
  [[ $got == "$want" ]] && printf 'ok   %s %q\n' "$fn" "$*" || { printf 'FAIL %s %q (want %s got %s)\n' "$fn" "$*" "$want" "$got"; fail=1; }
}
t 1 valid_realm corp.example.com;   t 1 valid_realm CORP.TEST;      t 0 valid_realm corp
t 0 valid_realm $'corp.test\n[x]';  t 0 valid_realm 'corp.test; rm -rf /'; t 0 valid_realm ''
t 1 valid_host dc.corp.test;        t 1 valid_host 10.0.2.2;         t 0 valid_host 'dc corp';   t 0 valid_host $'dc\nad_server=evil'
t 1 valid_admin Administrator;      t 1 valid_admin 'svc-join@corp.test'; t 1 valid_admin 'CORP\admin'
t 0 valid_admin 'a b';              t 0 valid_admin $'a\nb';         t 0 valid_admin 'a$(id)';   t 0 valid_admin 'a;b'
t 1 valid_list 'laptop-users';      t 1 valid_list 'laptop-users,IT Admins,svc.acct'; t 1 valid_list 'CORP\Domain Users'
t 0 valid_list '';                  t 0 valid_list ',a';             t 0 valid_list 'a,,b';      t 0 valid_list 'a,'
t 0 valid_list ' lead';             t 0 valid_list 'trail ';         t 0 valid_list $'a\nsimple_allow_users = evil'
t 0 valid_list 'a=b';               t 0 valid_list 'a;b';            t 0 valid_list 'a$(id)';    t 0 valid_list '#comment'
exit $fail
