# Roll out to a fleet

!!! warning "Prototype"
    Tested against Samba AD, not yet against Windows Active Directory or Omarchy's own login screen
    ([Status and limits](../status.md)). Pilot before you roll out.

This is the whole journey from "we have a directory and some Omarchy laptops" to "everyone signs in with their company
account, and we can see which laptops are in good shape". Read it once end to end, then follow the stages in order.
Each stage links to the detail.

| Stage | Goal | Who |
|---|---|---|
| 1. [Decide](#1-decide) | Make the handful of policy choices once | You |
| 2. [Prepare the directory](#2-prepare-the-directory) | A group, a place for laptops, a join account | Directory admin |
| 3. [Prepare the laptops](#3-prepare-the-laptops) | Unique names, working DNS and clock | You |
| 4. [Pilot](#4-pilot) | Prove it on a few machines, with a way back | You |
| 5. [Roll out](#5-roll-out) | Install and enroll everywhere, scripted | You or your MDM |
| 6. [Operate](#6-operate) | People come and go, laptops get replaced | Directory admin, you |
| 7. [Retire](#7-retire) | Take a laptop out cleanly | You |

## 1. Decide

You make these choices once, for the fleet. The recommendations are the safe defaults.

| Question | Recommendation | Why |
|---|---|---|
| **Who may sign in?** | One directory group, for example `laptop-users` (`--groups`). | A group is how access is granted and removed, in one place. Nobody can sign in until a group is named. Use `--users` only for a handful of machines, and `--mode any` (everyone in the directory) almost never. |
| **Where do laptops live in the directory?** | A dedicated OU, for example `OU=Laptops,DC=corp,DC=example,DC=com` (`--ou`). | Keeps computer accounts together so your delegation and policies apply to them. |
| **Which account joins laptops?** | A dedicated account that can create computer objects in that OU only. Not a Domain Admin. | Its password is typed or read once per enrollment and never stored; limit what it could do if leaked. |
| **Autologin?** | Leave it off (the default). Use `--keep-autologin` only for single-user machines. | Omarchy logs the first user in at boot by default; with company accounts you want the login screen. See [How sign-in works](../concepts/how-it-works.md#disk-encryption-and-autologin). |
| **Admin rights?** | Leave to your MDM. Use `--sudo-groups` only if you have no MDM. | This tool signs people in; it doesn't manage privilege. |
| **Offline?** | Allow it, optionally expiring after N days (`--offline-days`). | People work on planes. Expiry forces a reconnect to pick up changes. |
| **How do laptops get the package?** | A pacman repository you control, signed, or the packages from a [release](https://github.com/blatessa/monarchy-identity/releases). | Updates then arrive like any other package. |
| **What is "healthy"?** | Write a [compliance policy](compliance-checks.md) (disk encryption, firewall, autologin off, ...). | Lets you check the whole fleet with one command. |

## 2. Prepare the directory

Ask your directory administrator for three things. This tool doesn't create them, and they are standard directory
tasks:

1. **A security group** of the people allowed on these laptops (`laptop-users`). Optionally a second group for people
   who get `sudo` (`laptop-admins`). A group that is empty or misspelled admits nobody, and `enroll` stops before
   changing anything if it can't find the first group you name.
2. **An organizational unit** for the laptops' computer accounts.
3. **A join account** with the right to create and delete computer objects in that OU, and, if you will ever re-enroll a
   reinstalled laptop over its old account (`--replace-computer-account`), to reset passwords on them.

## 3. Prepare the laptops

On each laptop, before enrolling:

- **A unique hostname, at most 15 characters.** The hostname becomes the laptop's name in the directory, so two
  laptops with the same name would fight over one account. Names like `omarchy` or `archlinux` are refused. Set it
  with `sudo hostnamectl set-hostname laptop-0042`, or pass `--computer-name` at enrollment instead.
- **Working DNS for your domain.** Leave `--server` off in production: laptops find domain controllers through DNS
  (SRV records). Check with `dig -t SRV _ldap._tcp.corp.example.com`.
- **A network path to the domain controllers**, at least while enrolling and signing in for the first time. Typically
  DNS (53), Kerberos (88, 464), LDAP (389, TCP and UDP) and SMB (445); confirm against your own environment. A laptop that
  is only on a VPN, or only in the office, can only be enrolled there.
- **A correct clock** (network time on). Sign-in fails if the clock is off by more than about five minutes.
- **A local account with a password.** It is your way back in if anything is wrong, and enrollment refuses without it.

## 4. Pilot

Pilot on a virtual machine first, then on a few real laptops that you can reach if something goes wrong.

1. Enroll one machine ([Getting started](../getting-started.md)). Because you run it at a terminal, it starts a
   safety timer that undoes the enrollment unless you confirm. See [Enroll safely](enroll-safely.md).
2. Check each of these before confirming:
    - a person in the group signs in at the **login screen** and from a **text console** (Ctrl+Alt+F3);
    - a person **not** in the group is refused;
    - **locking and unlocking** the screen works with the directory password;
    - your **local account** still works;
    - after the first sign-in, **unplug the network** and sign in again (offline).
3. Run `sudo monarchy-identity leave --admin JOINACCOUNT` (with `--admin`, so the computer account is deleted), then enroll
   again. Both directions must work cleanly, because you will use both.
4. Repeat on two or three real laptops, including one you reinstalled. Reinstalled laptops reuse their hostname; see
   [Enroll safely](enroll-safely.md#existing-computer-accounts).

## 5. Roll out

**Deliver the package.** The package depends on `sssd`, `samba` and `krb5` from the Arch repositories. Releases ship two
packages: `monarchy-identity` (everything you need) and `monarchy-identity-shell` (an optional status widget). To install
by `pacman -S` on every laptop, host a small repository you control:

```bash
repo-add -s monarch.db.tar.zst monarchy-identity-*.pkg.tar.zst      # on a build host; -s signs it with your key
# serve the directory over HTTPS, then on each laptop add to /etc/pacman.conf:
#   [monarch]
#   Server = https://packages.example.com/monarch
sudo pacman -Sy monarchy-identity
```

Laptops must trust your signing key (`pacman-key`). Without a repository, `pacman -U` on the release files works for a
pilot.

**Enroll in waves.** Enroll a small wave, verify it with the checks in the pilot (and `monarchy-identity check`), then
the next. Keep the join account's password out of images and chat: your secrets manager or MDM supplies it for the
length of the run.

Scripted enrollment needs no terminal and is safe to run repeatedly. See [Automate enrollment](automation.md) for the
command, an Ansible example, and how the same command later updates policy on machines that are already enrolled.

Package delivery and enrollment are separate steps on purpose: installing the package changes nothing until you
enroll. A good pattern is to roll the package to everyone first, then enroll in waves.

## 6. Operate

**People come and go.** Add or remove people in the directory group. Nothing happens on laptops. A newly added person
signs in the next time they are online (laptops cache directory lookups, so it can take a little while); someone removed can still use cached credentials on a laptop until it next
reaches the directory, so set `--offline-days` if that window matters to you.

**Change the rules.** `monarchy-identity policy set` changes who may sign in on a laptop without re-joining
([Change who may sign in](change-policy.md)). With a script, re-running the same enrollment command does it for you.

**Know the state of the fleet.** `monarchy-identity status --json` is a machine-readable report for each laptop, and
`monarchy-identity check` turns your definition of "healthy" into pass or fail ([Compliance checks](compliance-checks.md)).
Collecting it is up to your tooling; for example `ssh laptop 'monarchy-identity check --json'` in a loop, or run `check`
as your MDM's compliance script.

**A laptop is reinstalled or replaced.** The new install has the same hostname, so the old computer account is in the
way. Delete the old account in the directory (cleanest), or enroll with `--replace-computer-account` if you are sure
it is the same laptop.

**Updates.** Omarchy updates can rewrite the files this tool manages. A watcher repairs them within seconds, so you
don't have to do anything ([Staying correct](../concepts/self-healing.md)).

## 7. Retire

`sudo monarchy-identity leave --admin JOINACCOUNT` returns the laptop to exactly how it was before enrolling and deletes
its computer account ([Leave and uninstall](leave-and-uninstall.md)). If a laptop is lost, delete its computer account in
the directory.

