# Who may sign in

A directory usually has far more people than any one laptop should admit. The **login policy** says which of them may
sign in on an enrolled laptop. It applies to every way of signing in (login screen, lock screen, terminal, `ssh`,
`sudo`).

**The default is deny:** when you enroll you must say who is allowed. There is no setting that quietly lets everyone in.

## Choosing

| You say | Who may sign in | Use it when |
|---|---|---|
| `--groups laptop-users` | Members of that directory group (or several: `--groups a,b`) | **Almost always.** Access is granted and removed in the directory, per person, for every laptop at once. |
| `--users alice,bob` | Only those people | A few machines, or a personal laptop. You edit each laptop to change it. |
| `--mode any` | Everyone in the directory | Rarely, and only if the directory itself is already limited to the right people. It must be asked for explicitly. |

Different laptops can use different groups (for example, one group per team), so the same directory serves different
fleets.

## What it doesn't cover

- **Local accounts.** They are never governed by this policy and always work, including when the directory is down.
  That is deliberate: it is your break-glass access.
- **Admin rights.** Signing in is separate from being an administrator. See
  [How sign-in works](how-it-works.md#admin-rights).
- **`su` and GPO rules.** Directory users can't `su`, and Group Policy based access rules aren't applied. See
  [Status and limits](../status.md).

## When a person is refused

A correct password for someone who isn't allowed fails the same way as a wrong password, and the login screen doesn't
say why. To find out, use `sudo monarchy-identity policy show` and check their group membership; see
[Troubleshooting](../guides/troubleshooting.md). The [test evidence](../evidence.md) shows a correct password being
accepted and the sign-in refused by policy.

## Changing it

[Change who may sign in](../guides/change-policy.md) shows how to change the policy on an enrolled laptop without
re-joining the directory.

## Names

People and groups are used by their short names (`alice`, `laptop-users`), not with the domain attached, and home
directories are `/home/<name>`. The names in group and user lists are separated by commas.
