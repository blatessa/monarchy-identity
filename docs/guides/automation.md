# Automate enrollment

Rolling out to many laptops means running one command on each, unattended. The pattern is:

1. Deliver the package (your pacman repository, or an MDM/Ansible install step).
2. Put the join account's password on the laptop in a root-only file for the duration of the run.
3. Run `enroll --if-needed`. It enrolls a new laptop, and on a laptop that's already enrolled it just brings the policy up
   to date, so you can run it on every machine, every time.
4. Remove the password file.

Scripted runs don't start the 10-minute safety timer (it exists for people at a terminal), so a script's result
stands. Add `--confirm-within N` if you want one anyway.

## Non-interactive input

- `--password-file FILE`, or the environment variable `OI_ADMIN_PASSWORD_FILE`, supplies the password (first line).
  The file must be a regular file (not a symlink), owned by root or the invoking user, with no group or other
  permissions (`chmod 600`).
- `leave` accepts `--admin` and `--password-file` the same way.
- Exit status is 0 on success and 1 on any failure. Messages go to stderr and to the journal
  (`journalctl -t monarchy-identity`).

## Idempotence with `--if-needed`

```bash
sudo monarchy-identity enroll --realm CORP.EXAMPLE.COM --admin joinuser \
  --ou 'OU=Laptops,DC=corp,DC=example,DC=com' \
  --groups laptop-users \
  --password-file /root/join.pw --if-needed
```

With `--if-needed`:

- If the machine is already enrolled in the same realm, `enroll` does not re-join and does not read the password. It
  applies the policy options through `policy set`, using them as the complete desired state: omitting `--sudo-groups`
  removes sudo access and omitting `--offline-days` resets it to 0. (This differs from [`policy set`](change-policy.md),
  where only the options you pass change.) Options about joining (`--ou`, `--computer-name`, `--server`,
  `--keep-login-theme`) are ignored on a machine that is already enrolled.
- Autologin is turned off, as at a normal enrollment, unless you pass `--keep-autologin`.
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

    - name: Enroll, or converge policy
      block:
        - name: Stage join credential
          ansible.builtin.copy:
            dest: /root/join.pw
            content: "{{ vault_join_password }}\n"
            mode: "0600"
          no_log: true

        - name: Run enroll
          ansible.builtin.command: >
            monarchy-identity enroll --realm CORP.EXAMPLE.COM --admin joinuser
            --ou "OU=Laptops,DC=corp,DC=example,DC=com" --groups laptop-users
            --password-file /root/join.pw --if-needed
          register: enroll
          changed_when: "'converging policy' not in enroll.stdout + enroll.stderr"
      always:
        - name: Remove credential
          ansible.builtin.file: { path: /root/join.pw, state: absent }
```

This sketch has not been run through Ansible; the command it wraps is exercised by `test/vm/e2e-noninteractive.sh` and
`test/vm/e2e-policy.sh`. On a machine that is already enrolled, `enroll --if-needed` logs
`converging policy`, so `changed_when` reports no change. The `always` section removes the credential even when enrollment fails.

## Reporting back

Read the machine's state with `monarchy-identity status --json` ([Posture report](../reference/posture.md)) or run
[`monarchy-identity check`](compliance-checks.md) as a compliance script.
