#!/bin/bash
# Unit tests for computer-account naming and OU handling (no VM, no root). Run: test/unit/naming.sh
cd "$(dirname "$0")/../.." || exit 1
export OI_ROOT=$PWD; source providers/sssd/lib.sh
fail=0
t() { local want=$1; shift; if "$@" >/dev/null 2>&1; then got=1; else got=0; fi
  [[ $got == "$want" ]] && printf 'ok   %s %q\n' "$1" "${*:2}" || { printf 'FAIL %s %q (want %s got %s)\n' "$1" "${*:2}" "$want" "$got"; fail=1; }; }
eq() { local want=$1 got; got=$(dn_to_createcomputer "$2"); [[ $got == "$want" ]] && printf 'ok   createcomputer %q -> %s\n' "$2" "$got" || { printf 'FAIL createcomputer %q: want %s got %s\n' "$2" "$want" "$got"; fail=1; }; }
for n in LAPTOP-0042 oi-client a A x 1abc a-b; do t 1 valid_computer_name "$n"; done
for n in -bad bad- 'a b' toolongcomputername1 '' 'a_b' 'a.b' $'a\nb' 'a;b'; do t 0 valid_computer_name "$n"; done
t 1 valid_ou_dn 'OU=Laptops,DC=corp,DC=test'
t 1 valid_ou_dn 'OU=Corp,OU=Laptops,DC=corp,DC=example,DC=com'
t 1 valid_ou_dn 'CN=Computers,DC=corp,DC=test'
t 1 valid_ou_dn 'OU=Sales Team,DC=corp,DC=test'
for dn in 'OU=a,DC=x;rm,DC=y' $'OU=a\n,DC=x' 'DC=corp,DC=test' 'OU=Laptops' 'OU=,DC=x,DC=y' 'OU=a"b,DC=x,DC=y' 'OU=a\,b,DC=x,DC=y' 'OU=a,DC=x,OU=b'; do t 0 valid_ou_dn "$dn"; done
eq 'Laptops' 'OU=Laptops,DC=corp,DC=test'
eq 'Laptops/Corp' 'OU=Corp,OU=Laptops,DC=corp,DC=example,DC=com'
eq 'Computers' 'CN=Computers,DC=corp,DC=test'
exit $fail
