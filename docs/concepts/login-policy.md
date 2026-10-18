# Who may sign in

A directory usually has far more people than any one laptop should admit. The **login policy** says which of them may
sign in on an enrolled laptop, everywhere people sign in: login screen, lock screen, terminal, `ssh` and `sudo`.

**Nobody is allowed by default.** When you enroll you say who is.

| You say | Who may sign in | Use it when |
|---|---|---|
| `--groups laptop-users` | Members of that directory group (or several: `--groups a,b`) | **Almost always.** You grant and remove access in the directory, for every laptop at once. |
| `--users alice,bob` | Only those people | A few machines, or a personal laptop. |
| `--mode any` | Everyone in the directory | Rarely: only if the directory itself holds just the right people. |

Different laptops can use different groups (one per team, for example). Use names the way your directory shows them;
Active Directory uses short names like `alice`.

The policy doesn't cover local accounts (they always work) or admin rights (`--sudo-groups`, see
[How sign-in works](how-it-works.md#admin-rights)). A correct password from someone who isn't allowed fails the same way
as a wrong one; [Troubleshooting](../guides/troubleshooting.md#a-directory-user-is-refused) shows how to tell them apart.

To change the policy on an enrolled laptop, see [Manage enrolled laptops](../guides/manage.md).
