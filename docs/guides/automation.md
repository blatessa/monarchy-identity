# Automate enrollment

To enroll many laptops, run one command on each, unattended:

1. Install the package (from your pacman repository, or an MDM/Ansible step).
2. Put the join account's password in a root-only file for the length of the run.
3. Run `enroll --if-needed`. On a new laptop it enrolls; on an enrolled one it brings the policy up to date. Run it on
   every machine, every time.
4. Delete the password file.

```bash
sudo monarchy-identity enroll --realm CORP.EXAMPLE.COM --admin joinuser \
  --ou 'OU=Laptops,DC=corp,DC=example,DC=com' \
  --groups laptop-users \
  --password-file /root/join.pw --if-needed
```

## Passwords

`--password-file FILE` (or the `OI_ADMIN_PASSWORD_FILE` environment variable) reads the password from the first line
of a file that only its owner can read (`chmod 600`). Without it, the password is read from standard input. `leave`
accepts `--admin` and `--password-file` the same way.

## Re-running with `--if-needed`

- **Already enrolled in the same realm:** no re-join and no password needed. The options you pass become the laptop's
  whole policy: leaving out `--sudo-groups` removes `sudo`, leaving out `--offline-days` removes the expiry. (With
  [`policy set`](change-policy.md), only what you pass changes.)
- **Enrolled in a different realm:** fails. Run `leave` first.
- **Not enrolled:** enrolls normally.

## Results

The exit status is 0 on success and 1 on failure, with the reason on standard error and in the journal
(`journalctl -t monarchy-identity`). Already-enrolled laptops log `converging policy without re-joining`.

To read a laptop's state from your tooling, use [`status --json`](../reference/status-output.md).

## Ansible

```yaml
- name: Enroll laptops
  hosts: omarchy_laptops
  become: true
  tasks:
    - name: Install package
      community.general.pacman: { name: monarchy-identity, state: present }

    - name: Enroll, or bring the policy up to date
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

This playbook hasn't been run through Ansible; the command it wraps is covered by the project's tests.
