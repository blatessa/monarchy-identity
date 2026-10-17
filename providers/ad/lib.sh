# Active Directory provider internals (joins with samba, signs in through sssd). Sourced by its scripts.
PROVIDER=ad
source "$OI_ROOT/lib/common.sh"
PAMEDIT="$OI_ROOT/lib/pamedit.py"
PAM_FILES=(system-auth omarchy-lock-password)

realm_lc() { echo "$1" | tr 'A-Z' 'a-z'; }

write_krb5() { # realm [server]   (no server => DNS SRV discovery of KDCs)
  local r=${1^^} d; d=$(realm_lc "$1")
  if [[ -n ${2:-} ]]; then
    cat > "$ETC/krb5.conf" <<K
$OI_MARK
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
$OI_MARK
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

write_smb() { # realm netbios-name
  local r=${1^^}
  mkdir -p "$ETC/samba"
  cat > "$ETC/samba/smb.conf" <<S
$OI_MARK
[global]
  workgroup = ${r%%.*}
  realm = $r
  netbios name = ${2:?netbios name required}
  security = ads
  kerberos method = secrets and keytab
  client use spnego = yes
S
}

write_sssd() { # realm server mode "groups" "users" hostfqdn netbios [offline_days]
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
$OI_MARK
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
  if [[ ${8:-0} =~ ^[1-9][0-9]*$ ]]; then
    printf '\n[pam]\noffline_credentials_expiration = %s\n' "$8" >> "$ETC/sssd/sssd.conf"
  fi
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
validate_enroll_args() { # realm server admin groups users
  valid_realm "$1" || die "invalid --realm '$1' (expected a DNS name like corp.example.com)"
  [[ -z $2 ]] || valid_host "$2" || die "invalid --server '$2'"
  valid_admin "$3" || die "invalid --admin '$3'"
  [[ -z $4 ]] || valid_list "$4" || die "invalid --groups '$4' (comma-separated names; letters, digits, . _ - @ space)"
  [[ -z $5 ]] || valid_list "$5" || die "invalid --users '$5' (comma-separated names; letters, digits, . _ - @ space)"
}

# --- directory lookups before joining ------------------------------------------------------------
# directory_missing_groups "g1,g2": prints the groups the directory does not have (uses $pw, $admin, SARGS).
# Exits non-zero if the directory cannot be searched at all (wrong password, DC unreachable). Group names may
# be written CORP\name or name@corp; the directory stores the bare sAMAccountName.
directory_missing_groups() {
  local g bare out IFS=,
  for g in $1; do
    bare=${g##*\\}; bare=${bare%%@*}
    out=$(printf '%s\n' "$pw" | net ads search "${SARGS[@]}" -U "$admin" "(&(objectClass=group)(sAMAccountName=$bare))" sAMAccountName 2>&1) \
      || { echo "$out" | tail -1 >&2; return 1; }
    grep -qi "^sAMAccountName: $bare\$" <<<"$out" || echo "$g"
  done
}

# --- computer account naming and placement ------------------------------------------------------
# A fleet's laptops each need a UNIQUE directory computer account. Joining with a name another machine already
# owns silently takes that account over (and breaks the other machine), so names are checked up front.
GENERIC_HOSTNAMES=(localhost localhost-localdomain archlinux omarchy arch)
valid_computer_name() { [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,13}[A-Za-z0-9])?$ || $1 =~ ^[A-Za-z0-9]$ ]]; }
pick_computer_name() { # pick_computer_name [override] -> echoes the NetBIOS name, or dies with a reason
  local override=${1:-} h g
  if [[ -n $override ]]; then
    valid_computer_name "$override" || die "invalid --computer-name '$override' (1-15 letters, digits or hyphens; not starting/ending with a hyphen)"
    echo "${override^^}"; return
  fi
  h=$(uname -n | cut -d. -f1)
  for g in "${GENERIC_HOSTNAMES[@]}"; do
    [[ ${h,,} == "$g" ]] && die "this machine's hostname is the generic '$h'; every laptop with that name would fight over one directory account. Set a unique hostname (hostnamectl set-hostname NAME) or pass --computer-name NAME"
  done
  (( ${#h} <= 15 )) || die "hostname '$h' is longer than 15 characters (the NetBIOS limit); two long hostnames would truncate to the same account. Use a shorter hostname or pass --computer-name NAME"
  valid_computer_name "$h" || die "hostname '$h' is not usable as a computer account name; pass --computer-name NAME"
  echo "${h^^}"
}
# --ou takes a DN (OU=Corp,OU=Laptops,DC=example,DC=com); samba's createcomputer= wants "Laptops/Corp" (top-down, no RDN keys).
valid_ou_dn() { [[ $1 =~ ^((OU|CN)=[A-Za-z0-9\ _.-]+,)+DC=[A-Za-z0-9-]+(,DC=[A-Za-z0-9-]+)*$ ]]; }
dn_to_createcomputer() {
  local rdn i out="" parts=() rdns
  IFS=, read -ra rdns <<<"$1"
  for rdn in "${rdns[@]}"; do
    case ${rdn^^} in OU=*|CN=*) parts+=("${rdn#*=}") ;; DC=*) ;; *) return 1 ;; esac
  done
  for ((i=${#parts[@]}-1; i>=0; i--)); do out+="${out:+/}${parts[i]}"; done
  echo "$out"
}

# --- persisted state ----------------------------------------------------------------------------
# sssd_save_state: writes /etc/monarchy-identity/config.toml from these globals:
#   realm server mode groups users disable_autologin keep_theme sudo_groups offline_days nb ou
sssd_save_state() {
  conf_write provider="$PROVIDER" login_mode="$mode" realm="$realm" server="$server" groups="$groups" users="$users" \
    autologin_disabled="$([[ ${disable_autologin:-0} == 1 ]] && echo true || echo false)" \
    login_theme="$([[ ${keep_theme:-0} == 1 ]] && echo stock || echo identity)" \
    sudo_groups="$sudo_groups" offline_days="$offline_days" computer_name="$nb" ou="${ou:-}"
}

# sssd_restart: (re)start sssd without ever tripping systemd's start-rate limit. Several quick restarts in a
# row (policy changes, reassert, restore paths; or an MDM looping over a fleet) hit "start-limit-hit" and leave
# sssd FAILED, which locks out every directory user until someone runs `systemctl reset-failed sssd`.
sssd_restart() {
  systemctl reset-failed sssd 2>/dev/null || true
  systemctl restart sssd
}

# wait_sssd_online DOMAIN [seconds]: after (re)starting sssd its backend needs a few seconds to reach the DC.
# Group lookups can succeed from the cache while it is still offline, so poll the backend state itself.
# Best effort: returns 1 on timeout (offline is a legitimate state, e.g. laptop away from the network).
# NEVER let sssctl read the terminal: if sssd is down it asks "Start SSSD now? (yes/no)" and would hang forever.
wait_sssd_online() {
  local d=$1 n=${2:-30} i
  for ((i=0; i<n; i++)); do
    systemctl is-active --quiet sssd || return 1
    timeout 5 sssctl domain-status "$d" </dev/null 2>/dev/null | grep -q 'Online status: Online' && return 0
    sleep 1
  done
  return 1
}
