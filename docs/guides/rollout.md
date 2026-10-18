# Roll out to a fleet

From "we have a directory and some Omarchy laptops" to "everyone signs in with their company account". Read it once,
then follow the stages in order.

## 1. Decide

| Question | Recommendation |
|---|---|
| **Who may sign in?** | One directory group, for example `laptop-users` (`--groups`). Use `--users` only for a handful of machines. |
| **Admin rights?** | A directory group for people who get `sudo` (`--sudo-groups laptop-admins`), or none. |
| **Offline sign-in?** | Allow it, optionally expiring after some days away (`--offline-days 14`). |
| **Autologin?** | Leave it off (the default). |
| **Where do laptops go in the directory, and which account enrolls them?** | See [Active Directory: prepare](../providers/ad.md#prepare-the-directory). |

## 2. Prepare

Set up the directory and check the laptops as on the [Active Directory page](../providers/ad.md#prepare-the-directory).

## 3. Pilot

Enroll a virtual machine, then a few real laptops ([Getting started](../getting-started.md)). On each, check that:

- a person in the group signs in at the **login screen** and on a **text console** (Ctrl+Alt+F3);
- a person **not** in the group is refused;
- **locking and unlocking** works with the directory password;
- after a first sign-in, signing in **with the network unplugged** works.

Then `leave` and enroll again, and try a reinstalled laptop: you'll do both in production.

## 4. Roll out

**Deliver the package** with `sudo pacman -S monarchy-identity` from Omarchy's package repository, already set up on
every Omarchy laptop, so updates arrive with the rest of the system. Until the package is there, use the file from a
[release](https://github.com/blatessa/monarchy-identity/releases). Installing changes nothing, so you can install
everywhere first and enroll afterwards.

**Enroll in waves**, with a script or your MDM: [Automate enrollment](automation.md).

## 5. Operate

- **People come and go:** add or remove them in the directory group. Someone removed can still use cached credentials
  on a laptop until it next reaches the directory; `--offline-days` limits that.
- **The rules change:** [Manage enrolled laptops](manage.md), or re-run your enrollment script.
- **A laptop is reinstalled:** enroll it again; see [Active Directory](../providers/ad.md#how-it-behaves) for its old
  computer account.
- **Updates:** nothing to do ([How sign-in works](../concepts/how-it-works.md#updates)).
- **Retiring a laptop:** [`leave`](manage.md#leave-the-directory). For a lost one, disable it in the directory.
