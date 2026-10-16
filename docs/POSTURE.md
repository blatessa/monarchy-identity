# Posture report (`monarchy-identity status --json`)

Stable, versioned JSON for MDM / osquery / Ansible. Additive changes keep `schema`; breaking changes bump it.
Read-only; works unprivileged. Anything not determinable is the string `"unknown"` (never a guess, never an error).
Some fields are stronger when run as root (`details.domain_joined` is `unknown` for non-root).

    {
      "schema": 1,
      "enrolled": true,                 // provider != local
      "provider": "sssd",
      "login_mode": "groups",           // groups | assigned | any | none
      "autologin": false,               // EFFECTIVE SDDM autologin (merged conf.d, last wins)
      "revert_pending": false,          // an unconfirmed --confirm-within timer is armed
      "self_heal": true,                // root-owned path unit is repairing drift
      "wheel_members": "root,admin",
      "details": {                      // provider-specific, from providers/<p>/status
        "sssd_active": "true", "nss_sss": "true", "pam_system_auth": "true",
        "pam_omarchy_lock_password": "true", "domain_joined": "true|false|unknown"
      },
      "device":  { "hostname": "...", "os": "Omarchy", "omarchy": "4.0.4-1", "kernel": "..." },
      "compliance": {
        "disk_encryption": "true|false|unknown",   // root fs on dm-crypt (LUKS), incl. LVM-on-LUKS
        "firewall": "active|inactive|unknown",     // ufw / firewalld / nftables service
        "secure_boot": "enabled|disabled|no-efi|unknown",
        "tpm2": "present|absent",
        "screen_lock_seconds": "300|unknown",      // invoking user's Omarchy idle.lock
        "time_sync": "true|false|unknown"          // clock NTP-synchronized (Kerberos fails past ~5 min skew)
      }
    }

Drift signal: any `details.pam_*` or `nss_sss` equal to `"false"` while `enrolled` is true.
Typical osquery/Ansible check: `monarchy-identity status --json | jq -e '.enrolled and .compliance.disk_encryption=="true"'`.
Probes live in `lib/posture.sh`; add a probe there and a line to this file.
