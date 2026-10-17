# Roll out to a fleet

!!! warning "Prototype"
    Tested against Samba AD, not yet against Windows Active Directory or Omarchy's own login screen
    ([Status and limits](../status.md)). Pilot before you roll out.

From "we have a directory and some Omarchy laptops" to "everyone signs in with their company account". Read it once,
then follow the stages in order.

## 1. Decide

| Question | Recommendation |
|---|---|
| **Who may sign in?** | One directory group, for example `laptop-users` (`--groups`). Use `--users` only for a handful of machines. |
| **Where do laptops go in the directory?** | A dedicated OU, for example `OU=Laptops,DC=corp,DC=example,DC=com` (`--ou`). |
| **Which account joins laptops?** | A dedicated account that can create computer objects in that OU, not a Domain Admin. Its password is used once per enrollment and never stored. |
| **Admin rights?** | A directory group for people who get `sudo` (`--sudo-groups laptop-admins`), or none. |
| **Offline sign-in?** | Allow it, optionally expiring after some days away (`--offline-days 14`). |
| **Autologin?** | Leave it off (the default). |
| **How do laptops get the package?** | A pacman repository you control, or the files from a [release](https://github.com/blatessa/monarchy-identity/releases). |

## 2. Prepare the directory

Ask your directory administrator for:

1. **A group** of the people allowed on these laptops (`laptop-users`), and optionally one for `sudo` (`laptop-admins`).
2. **An OU** for the laptops.
3. **A join account** that can create and delete computer objects in that OU (and reset their passwords, if you'll
   re-enroll reinstalled laptops).

## 3. Prepare the laptops

- **A unique hostname, at most 15 characters.** It becomes the laptop's name in the directory. Generic names like
  `omarchy` are refused. Set it with `sudo hostnamectl set-hostname laptop-0042`, or pass `--computer-name`.
- **DNS that finds your domain controllers.** Check with `dig -t SRV _ldap._tcp.corp.example.com`.
- **A network path to the domain controllers** while enrolling and for each person's first sign-in: typically DNS (53),
  Kerberos (88, 464), LDAP (389 TCP and UDP) and SMB (445).
- **A correct clock** (network time on). Sign-in fails when the clock is off by more than about five minutes.

## 4. Pilot

Enroll a virtual machine, then a few real laptops ([Getting started](../getting-started.md)). On each, check that:

- a person in the group signs in at the **login screen** and on a **text console** (Ctrl+Alt+F3);
- a person **not** in the group is refused;
- **locking and unlocking** works with the directory password;
- after a first sign-in, signing in **with the network unplugged** works.

Then `leave` and enroll again, and try a reinstalled laptop: you'll do both in production.

## 5. Roll out

**Deliver the package.** It depends only on Arch packages (`sssd`, `samba`, `krb5`). For `pacman -S` on every laptop,
host a signed repository:

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
- **A laptop is reinstalled:** its old computer account is still in the directory. Delete it there, or enroll with
  `--replace-computer-account` if you're sure it's the same laptop.
- **Updates:** nothing to do; see [Omarchy integration](omarchy-integration.md#updates).

## 7. Retire

`sudo monarchy-identity leave --admin joinuser` takes a laptop out of the directory and deletes its computer account
([Leave and uninstall](leave-and-uninstall.md)). For a lost laptop, delete its computer account in the directory.
