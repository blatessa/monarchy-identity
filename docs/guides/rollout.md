# Roll out to a fleet

!!! warning "Prototype"
    Only the Active Directory provider exists, tested against Samba AD, not yet against Windows Active Directory or
    Omarchy's own login screen ([Status and limits](../status.md)). Pilot before you roll out.

From "we have a directory and some Omarchy laptops" to "everyone signs in with their company account". Read it once,
then follow the stages in order. Where a step depends on your directory, the [provider page](../providers/index.md)
has the details.

## 1. Decide

| Question | Recommendation |
|---|---|
| **Who may sign in?** | One directory group, for example `laptop-users` (`--groups`). Use `--users` only for a handful of machines. |
| **Admin rights?** | A directory group for people who get `sudo` (`--sudo-groups laptop-admins`), or none. |
| **Offline sign-in?** | Allow it, optionally expiring after some days away (`--offline-days 14`). |
| **Autologin?** | Leave it off (the default). |
| **How do laptops get the package?** | A pacman repository you control, or the files from a [release](https://github.com/blatessa/monarchy-identity/releases). |
| **Directory-specific choices** | For example, in Active Directory, where laptops go and which account enrolls them. See your [provider](../providers/index.md). |

## 2. Prepare the directory

Every directory needs **a group** of the people allowed on these laptops (`laptop-users`), and optionally one for
`sudo` (`laptop-admins`). Anything else (an account that may enroll laptops, a place for them) is on the provider's
page, for example [Active Directory](../providers/ad.md#prepare-the-directory).

## 3. Prepare the laptops

- **A network path to the directory** while enrolling and for each person's first sign-in.
- **A correct clock** (network time on).
- Anything the provider adds, for example unique short hostnames for
  [Active Directory](../providers/ad.md#prepare-the-laptops).

## 4. Pilot

Enroll a virtual machine, then a few real laptops ([Getting started](../getting-started.md)). On each, check that:

- a person in the group signs in at the **login screen** and on a **text console** (Ctrl+Alt+F3);
- a person **not** in the group is refused;
- **locking and unlocking** works with the directory password;
- after a first sign-in, signing in **with the network unplugged** works.

Then `leave` and enroll again, and try a reinstalled laptop: you'll do both in production.

## 5. Roll out

**Deliver the package.** It depends only on Arch packages. For `pacman -S` on every laptop, host a signed repository:

```bash
repo-add -s monarch.db.tar.zst monarchy-identity-*.pkg.tar.zst
# serve it over HTTPS; on each laptop, in /etc/pacman.conf:
#   [monarch]
#   Server = https://packages.example.com/monarch
sudo pacman -Sy monarchy-identity
```

**Enroll in waves**, with a script or your MDM: [Automate enrollment](automation.md). Installing the package changes
nothing, so you can roll the package out to everyone first and enroll afterwards.

## 6. Operate

- **People come and go:** add or remove them in the directory group. Nothing to do on the laptops. Someone removed can
  still use cached credentials on a laptop until it next reaches the directory; `--offline-days` limits that.
- **The rules change:** [Change who may sign in](change-policy.md), or re-run your enrollment script.
- **A laptop is reinstalled:** enroll it again. Some directories remember the old laptop; the provider page says what
  to do (for example [Active Directory](../providers/ad.md#how-it-behaves)).
- **Updates:** nothing to do; see [Omarchy integration](omarchy-integration.md#updates).

## 7. Retire

`sudo monarchy-identity leave` disconnects a laptop from the directory ([Leave and uninstall](leave-and-uninstall.md)).
For a lost laptop, remove or disable it in the directory.
