# Change who may sign in

`policy set` changes the rules on an enrolled laptop without re-joining the directory and without the join password.
(To add or remove *people*, change the directory group instead.)

```bash
monarchy-identity policy show                                        # what's in force now
sudo monarchy-identity policy set --groups laptop-users,contractors  # also allow the contractors group
sudo monarchy-identity policy set --users alice,bob                  # only these people
sudo monarchy-identity policy set --sudo-groups laptop-admins        # this group gets sudo
sudo monarchy-identity policy set --sudo-groups -                    # nobody from the directory gets sudo
sudo monarchy-identity policy set --offline-days 14                  # cached sign-in expires after 14 days away
```

![policy show output](../img/policy.png)

- **Only what you pass changes.** Everything else keeps its current value.
- **Naming groups or users picks the kind of policy.** `--groups` means "members of these groups", `--users` means
  "only these people", `--mode any` opens it to the whole directory.
- **Mistakes are refused.** A group the directory doesn't have, or a change that would let nobody in, is refused and
  nothing changes.
- **Offline is fine.** If the directory can't be reached, the new policy still applies, and takes effect once the
  laptop reconnects.

## Sudo

`--sudo-groups` gives members of those directory groups full `sudo` on the laptop. Group names here may use letters,
digits, `.`, `_` and `-`.
