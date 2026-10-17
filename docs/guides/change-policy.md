# Change who may sign in

`policy set` changes the login policy on an enrolled machine without re-joining the domain and without directory
credentials.

Use it when the rules change for a laptop that is already enrolled: another group may now sign in, `sudo` is granted or
removed, or cached sign-in should expire sooner. (Adding or removing *people* is done in the directory group, not here.)

```bash
sudo monarchy-identity policy show                                   # what is in force now
sudo monarchy-identity policy set --groups laptop-users,contractors  # also allow the contractors group
sudo monarchy-identity policy set --users alice,bob                  # switch to a fixed list of people
sudo monarchy-identity policy set --sudo-groups laptop-admins        # this group gets sudo
sudo monarchy-identity policy set --sudo-groups -                    # remove sudo access
sudo monarchy-identity policy set --offline-days 14                  # cached sign-in expires after 14 days away
```

![policy show output](../img/policy.png)

`policy show` needs no privileges. `policy set` needs root.

## How it behaves

- **Only what you pass changes.** The rest keeps its current value. (Re-running `enroll --if-needed` in a script works the
  other way: its options are the full desired state, see [Automate enrollment](automation.md).)
- **A safe change.** The new policy is applied and checked: in group mode the first group you name must be found in the
  directory within 30 seconds, otherwise the previous policy is restored and the command fails. A change that would leave
  nobody allowed is refused.
- **Naming groups or users picks the kind of policy.** `--groups` means "members of these groups", `--users` means "only
  these people", and `--mode any` opens it to the whole directory.
- **No re-join.** The laptop's computer account isn't touched and no directory credentials are needed.
- **Directory unreachable?** The policy is still applied (with a warning) and takes effect when the laptop reconnects.

## Sudo

`--sudo-groups` gives the members of those directory groups full `sudo` on this laptop. The rule is checked before it is
installed. Group names are limited to letters, digits, `.`, `_` and `-`. If your MDM manages privilege, leave this off.
