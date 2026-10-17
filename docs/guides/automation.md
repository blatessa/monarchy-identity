# Automate enrollment

`enroll` needs no terminal when the join password comes from a file.

## Non-interactive input

- `--password-file FILE`, or the environment variable `OI_ADMIN_PASSWORD_FILE`, supplies the password (first line).
  The file must be a regular file (not a symlink), owned by root or the invoking user, with no group or other
  permissions (`chmod 600`).
- `leave` accepts `--admin` and `--password-file` the same way.
- Exit status is 0 on success and 1 on any failure. Messages go to stderr and to the journal
  (`journalctl -t monarchy-identity`).

## Idempotence with `--if-needed`

```bash
sudo monarchy-identity enroll sssd --realm CORP.EXAMPLE.COM --admin joinuser \
  --ou 'OU=Laptops,DC=corp,DC=example,DC=com' \
  --mode groups --groups laptop-users --disable-autologin \
  --password-file /root/join.pw --if-needed
```

With `--if-needed`:

- If the machine is already enrolled in the same realm, `enroll` does not re-join and does not read the password. It
  applies the given policy through `policy set`, using the arguments as the complete desired state: omitting
  `--sudo-groups` removes sudo access and omitting `--offline-days` resets it to 0.
- `--disable-autologin` is applied when passed; omitting it never re-enables autologin.
- If the machine is enrolled in a different realm, it fails; run `leave` first.
- If the machine is not enrolled, it enrolls normally.

## Ansible

```yaml
- name: Enroll laptops
  hosts: omarchy_laptops
  become: true
  tasks:
    - name: Install package
      community.general.pacman: { name: monarchy-identity, state: present }

    - name: Stage join credential
      ansible.builtin.copy:
        dest: /root/join.pw
        content: "{{ vault_join_password }}\n"
        mode: "0600"
      no_log: true

    - name: Enroll, or converge policy
      ansible.builtin.command: >
        monarchy-identity enroll sssd --realm CORP.EXAMPLE.COM --admin joinuser
        --ou "OU=Laptops,DC=corp,DC=example,DC=com" --mode groups --groups laptop-users
        --disable-autologin --password-file /root/join.pw --if-needed
      register: enroll
      changed_when: "'enrolled in' in enroll.stdout + enroll.stderr"

    - name: Remove credential
      ansible.builtin.file: { path: /root/join.pw, state: absent }
```

This sketch has not been run through Ansible; the command it wraps is exercised by `test/vm/e2e-noninteractive.sh` and
`test/vm/e2e-policy.sh`. On a machine that is already enrolled, `enroll --if-needed` logs
`already enrolled in ...: converging policy`, so `changed_when` reports no change.

## Reporting back

Read the machine's state with `monarchy-identity status --json` ([Posture report](../reference/posture.md)) or run
[`monarchy-identity check`](compliance-checks.md) as a compliance script.
