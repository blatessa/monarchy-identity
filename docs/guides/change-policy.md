# Change who may sign in

`policy set` changes the login policy on an enrolled machine without re-joining the domain and without directory
credentials.

```bash
sudo monarchy-identity policy show
sudo monarchy-identity policy set --mode groups --groups laptop-users,contractors
sudo monarchy-identity policy set --mode assigned --users alice,bob
sudo monarchy-identity policy set --sudo-groups laptop-admins
sudo monarchy-identity policy set --sudo-groups -          # remove sudo access
sudo monarchy-identity policy set --offline-days 14
```

![policy show output](../img/policy.png)

`policy show` needs no privileges. `policy set` requires root.

- Only the options you pass change; the rest keep their saved values.
- The new `sssd.conf` is written and sssd restarted. In `groups` mode the first listed group must resolve within 30
  seconds; if it does not, the previous `sssd.conf` is restored and the command fails.
- A change that leaves `--mode groups` without groups, or `--mode assigned` without users, is refused.
- If the domain controller is unreachable, sssd may not report online within 30 seconds. The policy is applied
  anyway and takes effect when sssd reconnects (a warning is logged).
- The computer account is not touched: `pwdLastSet` is unchanged.

`--sudo-groups` writes `/etc/sudoers.d/50-monarchy-identity`, validated with `visudo -cf` before installation, with
one `%group ALL=(ALL:ALL) ALL` line per group. Group names are limited to letters, digits, `.`, `_` and `-`.
