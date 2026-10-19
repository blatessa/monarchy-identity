# Entra ID provider helpers (himmelblau). Sourced, not executed.
source "$OI_ROOT/lib/common.sh"

HB_CONF="$ETC/himmelblau/himmelblau.conf"
HB_UNITS=(himmelblaud himmelblaud-tasks)
# Talks to Entra (tenant discovery, group and user lookups); the fast tests swap in a stub.
GRAPH="${MONARCHY_IDENTITY_ENTRA_GRAPH:-$OI_ROOT/providers/entra/graph.py}"
graph() { if [[ $GRAPH == *.py ]]; then python3 -I "$GRAPH" "$@"; else "$GRAPH" "$@"; fi; }

need_himmelblau() {
  aad-tool version >/dev/null 2>&1 \
    || die "the Entra ID client (himmelblau) is not installed: sudo pacman -S himmelblau"
}

# --- input validation ---------------------------------------------------------------------------
# These values are written into himmelblau.conf (the core validates --groups / --users).
valid_tenant()    { [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ && $1 == *.* ]]; }
valid_client_id() { [[ $1 =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; }

# Entra signs people in with their full name (alice@corp.example.com); a bare name gets the tenant's domain.
upns() { # upns "u1,u2" TENANT -> comma list of sign-in names
  local u out="" IFS=,
  for u in $1; do [[ $u == *@* ]] || u="$u@$2"; out+="${out:+,}$u"; done
  printf '%s\n' "$out"
}

# resolve_policy_ids TENANT CLIENT_ID: sets ALLOW (what pam_allow_groups gets: group ids or sign-in names; empty for
# --mode any) and GROUP_IDS (name=id,...). Group names need a lookup in Entra, so the app registration's secret is
# read (core's --password-file, or stdin); it is used for this and not kept.
resolve_policy_ids() {
  ALLOW="" GROUP_IDS=""
  case $mode in
    any) return 0 ;;
    groups) [[ -n $2 ]] || die "--client-id is required to look up the groups in Entra (an app registration with Group.Read.All; see the Entra provider docs)" ;;
    assigned) ALLOW=$(upns "$users" "$1"); [[ -n $2 ]] || return 0 ;;
  esac
  read_admin_password "Client secret of the app registration"
  local out kind name id
  local g=""; [[ $mode != groups ]] || g=$groups   # the other mode's names stay in config.toml; they don't count
  out=$(printf '%s\n' "$pw" | graph resolve "$1" "$2" --groups "$g" --users "${ALLOW:-}") || exit 1
  pw=""
  while IFS=$'\t' read -r kind name id; do
    [[ $kind == group ]] || continue
    ALLOW+="${ALLOW:+,}$id"; GROUP_IDS+="${GROUP_IDS:+,}$name=$id"
  done <<<"$out"
}

write_himmelblau_conf() { # write_himmelblau_conf TENANT ALLOW
  # Password sign-in with the offline cache (offline_breakglass caches a verifier on every online sign-in; without it
  # offline only works for the very first sign-in). Hello PIN waits for a login screen that can ask for one.
  local allow=""
  [[ -z $2 ]] || allow="pam_allow_groups = $2"$'\n'
  install -d -m 0755 "$(dirname "$HB_CONF")"
  write_if_changed "$HB_CONF" "$OI_MARK
[global]
domain = $1
${allow}enable_hello = false

[offline_breakglass]
enabled = true"
}

# himmelblau must answer passwd, group and shadow (pam_unix's account check reads shadow).
nss_apply() {
  local f="$ETC/nsswitch.conf" k
  for k in passwd group shadow; do
    grep -qE "^$k:.*\bhimmelblau\b" "$f" || sed -i -E "s/^($k:.*)$/\1 himmelblau/" "$f"
  done
}
nss_remove() { sed -i -E '/^(passwd|group|shadow):/ s/[[:space:]]+himmelblau\b//' "$ETC/nsswitch.conf"; }

hb_start() {
  systemctl enable --now "${HB_UNITS[@]}" >/dev/null 2>&1 || die "could not start the himmelblau daemons (journalctl -u himmelblaud)"
  timeout 30 bash -c 'until aad-tool status >/dev/null 2>&1; do sleep 1; done' \
    || die "the himmelblau daemon did not come up (journalctl -u himmelblaud); sign-in is not switched on. Re-run this command"
}
