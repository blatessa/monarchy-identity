# Who may sign in

A directory usually has far more people than any one laptop should admit. The **login policy** says which of them may
sign in on an enrolled laptop. It applies everywhere people sign in: login screen, lock screen, terminal, `ssh` and
`sudo`.

**Nobody is allowed by default.** When you enroll you say who is.

## Choosing

| You say | Who may sign in | Use it when |
|---|---|---|
| `--groups laptop-users` | Members of that directory group (or several: `--groups a,b`) | **Almost always.** You grant and remove access in the directory, for every laptop at once. |
| `--users alice,bob` | Only those people | A few machines, or a personal laptop. |
| `--mode any` | Everyone in the directory | Rarely: only if the directory itself holds just the right people. |

Different laptops can use different groups (one per team, for example).

## Names

Use short names (`alice`, `laptop-users`), not names with the domain attached. Separate several with commas. Home
folders are `/home/<name>`.

## What it doesn't cover

- **Local accounts.** They always work and aren't affected by the policy.
- **Admin rights.** Being allowed to sign in is separate from `sudo`; see
  [How sign-in works](how-it-works.md#admin-rights).
- **`su` and Group Policy logon rules.** Not supported yet; see [Status and limits](../status.md).

## When someone is refused

A correct password for someone who isn't allowed fails the same way as a wrong password. To find out why, see
[Troubleshooting](../guides/troubleshooting.md#a-directory-user-is-refused).

To change the policy on an enrolled laptop, see [Change who may sign in](../guides/change-policy.md).
