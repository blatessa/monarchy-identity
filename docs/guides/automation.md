# Automate enrollment

To enroll many laptops, run one command on each, unattended:

1. Install the package (from your pacman repository, or an MDM/Ansible step).
2. If your provider needs a credential to enroll (Active Directory's join account does), put it in a root-only file
   for the length of the run.
3. Run `enroll --if-needed`. On a new laptop it enrolls; on an enrolled one it brings the policy up to date. Run it on
   every machine, every time.
4. Delete the password file.

With Active Directory:

```bash
sudo monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser \
  --ou 'OU=Laptops,DC=corp,DC=example,DC=com' \
  --groups laptop-users \
  --password-file /root/join.pw --if-needed
```

## Credentials

`--password-file FILE` (or the `OI_ADMIN_PASSWORD_FILE` environment variable) reads a provider's enrollment password
from the first line of a file that only its owner can read (`chmod 600`). Without it, the password is read from
standard input. Never pass a password as an argument. Which credential a provider needs, if any, is on its page.

## Re-running with `--if-needed`

- **Already enrolled with the same directory:** nothing is re-registered and no credential is needed. The options you pass become the laptop's
  whole policy: leaving out `--sudo-groups` removes `sudo`, leaving out `--offline-days` removes the expiry, and
  `--keep-autologin` and `--keep-login-theme` apply as on a new laptop. (With
  [`policy set`](change-policy.md), only what you pass changes.)
- **Enrolled with a different directory:** fails. Run `leave` first.
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
            monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser
            --ou "OU=Laptops,DC=corp,DC=example,DC=com" --groups laptop-users
            --password-file /root/join.pw --if-needed
          register: enroll
          changed_when: "'converging policy' not in enroll.stdout + enroll.stderr"
      always:
        - name: Remove credential
          ansible.builtin.file: { path: /root/join.pw, state: absent }
```

This playbook hasn't been run through Ansible; the command it wraps is covered by the project's tests.
