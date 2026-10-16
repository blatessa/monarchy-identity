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
