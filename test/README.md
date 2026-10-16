# Test environment

Directory: Samba AD (CORP.TEST) in Docker, published on 127.0.0.1 only.
Client: Arch cloud image under QEMU/KVM, UEFI, user-mode net (host = 10.0.2.2).

    test/dc:   docker compose up -d && ./seed-users.sh
    test/vm:   ./fetch-image.sh   # once, checksum-verified
               ./run.sh           # boots VM; ssh -i keys/id_oi -p 2222 tester@127.0.0.1

Users (password Passw0rd!Test): alice (allowed, oi-admins), bob (allowed), carol (directory only: must be denied).
Admin password: Passw0rd!Test (throwaway, loopback-only DC).
VM guest resolves dc.corp.test -> 10.0.2.2 via /etc/hosts.

Findings:
- sssd, samba, krb5 are in Arch `extra`; adcli and oddjob are AUR-only.
  => sssd provider joins with `net ads join` and uses pam_mkhomedir, no AUR dependency.

Scripts: vm/deploy.sh [--fixtures], vm/e2e.sh, vm/e2e-modes.sh, vm/trylogin.sh USER PW, vm/pamtest.py SERVICE USER PW.
See ../HANDOFF.md for status and findings.
