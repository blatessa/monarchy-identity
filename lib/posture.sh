# Read-only device posture probes for `monarchy-identity status --json`. Sourced, not executed.
# Every probe prints one token; anything it cannot determine is "unknown" (never a guess, never an error).

posture_disk_encryption() { # true | false | unknown  -- is the root filesystem on a dm-crypt (LUKS) device?
  local src; src=$(findmnt -no SOURCE / 2>/dev/null) || { echo unknown; return; }
  src=${src%%\[*}                                    # btrfs reports /dev/mapper/root[/@]
  [[ -b $src ]] || { echo unknown; return; }
  # walk up the device stack: root may be LVM on LUKS, etc.
  if lsblk -rnso TYPE "$src" 2>/dev/null | grep -qx crypt; then echo true; else echo false; fi
}

posture_firewall() { # active | inactive | unknown (ufw, firewalld, nftables-service)
  local u
  for u in ufw firewalld nftables; do
    systemctl cat "$u.service" >/dev/null 2>&1 || continue
    systemctl is-active --quiet "$u" && { echo "active"; return; }
  done
  systemctl cat ufw.service >/dev/null 2>&1 || systemctl cat firewalld.service >/dev/null 2>&1 || systemctl cat nftables.service >/dev/null 2>&1 \
    && echo inactive || echo unknown
}

posture_secure_boot() { # enabled | disabled | no-efi | unknown
  [[ -d /sys/firmware/efi ]] || { echo no-efi; return; }
  local f; f=$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | head -1)
  [[ -r $f ]] || { echo unknown; return; }
  [[ $(od -An -tu1 -j4 -N1 "$f" 2>/dev/null | tr -d ' ') == 1 ]] && echo enabled || echo disabled
}

posture_tpm2() { [[ -e /dev/tpmrm0 ]] && echo present || echo absent; }

posture_screen_lock_seconds() { # idle.lock from the invoking user's Omarchy shell.json (user-level; "unknown" if unset)
  local f="${HOME:-/nonexistent}/.config/omarchy/shell.json" v=""
  [[ -r $f ]] && v=$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("idle",{}).get("lock",""))' "$f" 2>/dev/null)
  [[ $v =~ ^[0-9]+$ ]] && echo "$v" || echo unknown
}

posture_os() { ( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}" ); }
posture_omarchy_version() { omarchy-version 2>/dev/null || echo unknown; }

posture_time_sync() { # true | false | unknown -- is the clock NTP-synchronized? (Kerberos fails beyond ~5 min of skew)
  local v; v=$(timedatectl show -p NTPSynchronized --value 2>/dev/null) || { echo unknown; return; }
  case $v in yes) echo true;; no) echo false;; *) echo unknown;; esac
}
