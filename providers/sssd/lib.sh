# sssd provider internals. Sourced by enroll/unenroll/reassert/status.
source "$OI_ROOT/lib/common.sh"
PAMEDIT="$OI_ROOT/lib/pamedit.py"
PAM_FILES=(system-auth omarchy-lock-password)
MANAGED=(/etc/nsswitch.conf /etc/krb5.conf /etc/samba/smb.conf /etc/sssd/sssd.conf /etc/krb5.keytab
         /etc/pam.d/system-auth /etc/pam.d/omarchy-lock-password)

realm_lc() { echo "$1" | tr 'A-Z' 'a-z'; }

write_krb5() { # realm [server]   (no server => DNS SRV discovery of KDCs)
  local r=${1^^} d; d=$(realm_lc "$1")
  if [[ -n ${2:-} ]]; then
    cat > "$ETC/krb5.conf" <<K
[libdefaults]
  default_realm = $r
  dns_lookup_realm = false
  dns_lookup_kdc = false
  rdns = false
[realms]
  $r = {
    kdc = $2
    admin_server = $2
  }
[domain_realm]
  .$d = $r
  $d = $r
K
  else
    cat > "$ETC/krb5.conf" <<K
[libdefaults]
  default_realm = $r
  dns_lookup_realm = true
  dns_lookup_kdc = true
  rdns = false
[domain_realm]
  .$d = $r
  $d = $r
K
  fi
}

# server_args: sets SARGS=(-S server) or () so samba tools use DNS discovery when no server is configured.
server_args() { SARGS=(); [[ -n ${1:-} ]] && SARGS=(-S "$1"); return 0; }

write_smb() { # realm
  local r=${1^^}
  mkdir -p "$ETC/samba"
  cat > "$ETC/samba/smb.conf" <<S
[global]
  workgroup = ${r%%.*}
  realm = $r
  security = ads
  kerberos method = secrets and keytab
  client use spnego = yes
S
}

write_sssd() { # realm server mode "groups" "users" hostfqdn netbios
  local r=${1^^} d; d=$(realm_lc "$1")
  local access="" mode=$3
  case $mode in
    groups)   access=$'access_provider = simple\nsimple_allow_groups = '"$4" ;;
    assigned) access=$'access_provider = simple\nsimple_allow_users = '"$5" ;;
    any)      access="access_provider = permit" ;;
    *) die "unknown login mode '$mode' (assigned|groups|any)" ;;
  esac
  local adsrv=""; [[ -n $2 ]] && adsrv="ad_server = $2"
  install -d -m 0711 "$ETC/sssd"
  umask 077
  cat > "$ETC/sssd/sssd.conf" <<S
[sssd]
services = nss, pam
domains = $d

[domain/$d]
id_provider = ad
auth_provider = ad
chpass_provider = ad
$access
ad_domain = $d
krb5_realm = $r
$adsrv
ad_hostname = $6
ldap_sasl_authid = ${7}\$
ad_gpo_access_control = disabled
dyndns_update = false
use_fully_qualified_names = False
fallback_homedir = /home/%u
default_shell = /bin/bash
ldap_id_mapping = True
cache_credentials = True
krb5_store_password_if_offline = True
S
  chmod 0600 "$ETC/sssd/sssd.conf"
}

nss_apply() {
  local f="$ETC/nsswitch.conf" k
  for k in passwd group shadow; do
    grep -qE "^$k:.*\bsss\b" "$f" || sed -i -E "s/^($k:[[:space:]]*files)/\1 sss/" "$f"
  done
}
nss_remove() { sed -i -E '/^(passwd|group|shadow):/ s/[[:space:]]+sss\b//' "$ETC/nsswitch.conf"; }

pam_apply()  { local f; for f in "${PAM_FILES[@]}"; do [[ -f $ETC/pam.d/$f ]] && python3 -I "$PAMEDIT" apply "$ETC/pam.d/$f"; done; return 0; }
pam_remove() { local f; for f in "${PAM_FILES[@]}"; do [[ -f $ETC/pam.d/$f ]] && python3 -I "$PAMEDIT" remove "$ETC/pam.d/$f"; done; return 0; }

# --- input validation ---------------------------------------------------------------------------
# These values are written into sssd.conf / smb.conf / krb5.conf. Reject anything that could inject
# extra config lines or shell metacharacters; names are restricted to what directories really use.
valid_host()  { [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]]; }
valid_realm() { [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ && $1 == *.* ]]; }
valid_admin() { [[ $1 =~ ^[A-Za-z0-9._@\\-]{1,128}$ ]]; }
valid_list()  { # comma-separated names; letters digits . _ - @ space \ ; no leading/trailing space, no empties
  local item IFS=,; [[ -n $1 ]] || return 1
  for item in $1; do
    [[ $item =~ ^[A-Za-z0-9._@\\-]([A-Za-z0-9._@\\ -]{0,126}[A-Za-z0-9._@\\-])?$ ]] || return 1
  done
  [[ $1 != *,, && $1 != ,* && $1 != *,  ]]
}
validate_enroll_args() { # realm server admin groups users confirm_within
  valid_realm "$1" || die "invalid --realm '$1' (expected a DNS name like corp.example.com)"
  [[ -z $2 ]] || valid_host "$2" || die "invalid --server '$2'"
  valid_admin "$3" || die "invalid --admin '$3'"
  [[ -z $4 ]] || valid_list "$4" || die "invalid --groups '$4' (comma-separated names; letters, digits, . _ - @ space)"
  [[ -z $5 ]] || valid_list "$5" || die "invalid --users '$5' (comma-separated names; letters, digits, . _ - @ space)"
  [[ $6 =~ ^[0-9]+$ ]] || die "invalid --confirm-within '$6' (whole minutes)"
}
