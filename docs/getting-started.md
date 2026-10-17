# Getting started

By the end of this page one Omarchy laptop is joined to your Active Directory domain, and a directory user can sign in
on it. It takes a short while. Use a spare laptop or a virtual machine first: this tool edits the login (PAM)
configuration. A safety timer reverts the change if you don't confirm it, and you keep a local account that always works.

Want to know what this changes on the laptop first? Read [How sign-in works on Omarchy](concepts/how-it-works.md).

The example values below are `CORP.EXAMPLE.COM` (your domain), `joinuser` (an account that may join computers),
`laptop-users` (the group allowed to sign in) and `alice` (a member of that group). Replace them with yours.

## 1. Prepare the directory (once, on a domain controller or admin workstation)

You need two things in the directory:

1. **A group of people who may sign in**, here `laptop-users`. The default policy is deny: nobody can sign in unless
   they are in a group you name. Add `alice` to it.
2. **An account that may join computers**, here `joinuser`. It should be able to create computer objects, not be a
   Domain Admin. For a first test, an existing administrator account is fine.

On Samba AD:

```bash
samba-tool group add laptop-users
samba-tool group addmembers laptop-users alice
```

On Windows AD (not yet tested with this tool), the same in PowerShell: `New-ADGroup laptop-users -GroupScope Global`
and `Add-ADGroupMember laptop-users alice`.

## 2. Check the laptop

On the laptop, run these and fix anything that's off:

```bash
hostnamectl hostname        # must be unique, at most 15 characters; not "omarchy" or "archlinux"
timedatectl                 # "System clock synchronized: yes" (Kerberos fails if the clock is off by 5+ minutes)
dig -t SRV _ldap._tcp.corp.example.com   # the laptop's DNS must find your domain controllers
```

If the hostname is wrong: `sudo hostnamectl set-hostname laptop-0042`. The hostname becomes the computer's name in
the directory. You also need a local user with a password (you probably have one: it's your normal account).

## 3. Install

Download the two `.pkg.tar.zst` files and `SHA256SUMS` from the
[releases page](https://github.com/blatessa/monarchy-identity/releases), then:

```bash
sha256sum -c --ignore-missing SHA256SUMS
sudo pacman -U monarchy-identity-*.pkg.tar.zst
```

(Or build it: `git clone https://github.com/blatessa/monarchy-identity && cd monarchy-identity/packaging && makepkg -si`.)
Installing changes nothing yet.

## 4. Enroll

```bash
sudo monarchy-identity enroll \
  --realm CORP.EXAMPLE.COM --admin joinuser \
  --groups laptop-users
```

`--groups` says who may sign in. The command asks for `joinuser`'s password, joins the domain, and configures sign-in. If
anything fails, it undoes everything and removes the computer account it created. When it finishes it prints
`enrolled in CORP.EXAMPLE.COM`.

Omarchy normally signs its local user in automatically at boot. Enrolling turns that off so the login screen appears and
people can sign in as themselves ([why](concepts/how-it-works.md#disk-encryption-and-autologin)); add `--keep-autologin`
if you'd rather keep it.

Because you ran it at a terminal, it also starts a 10-minute safety timer. If you do nothing, the laptop **leaves the
domain by itself**, so a bad enrollment can't lock you out. Step 6 cancels the timer. (The timer can't delete the laptop's
computer account in the directory, because it has no password. If it fires, delete that account in the directory, or add
`--replace-computer-account` when you enroll again.)

## 5. Sign in as a directory user

Don't test from the session you enrolled in. Open a text console with **Ctrl+Alt+F3** and log in as `alice` with her
directory password. (Ctrl+Alt+F1 or F2 returns to the graphical screen.) The first login takes a few seconds because
her home directory is created.

The Omarchy login screen works too: it now has a username box above the password box.

Check that the policy is enforced: log in as a directory user who is **not** in `laptop-users`. The login must fail.
Your local account must still work.

You can also look at the state any time, no root needed:

```bash
monarchy-identity status
```

![status output after enrollment](img/status.png)

`enrolled: true` and `login mode: groups` mean it's in place. `revert pending: true` means the safety timer is still running.

## 6. Confirm

When `alice` could sign in and a non-member couldn't, cancel the revert timer:

```bash
sudo monarchy-identity confirm
```

Done: the laptop is enrolled. If something went wrong instead, undo it now with
`sudo monarchy-identity leave --admin joinuser` (with `--admin`, so the computer account is removed too).

## What now

| You want to | Read |
|---|---|
| Do this for many laptops | [Roll out to a fleet](guides/rollout.md), then [Automate enrollment](guides/automation.md) |
| Change who may sign in later | [Change who may sign in](guides/change-policy.md) |
| Report or check laptop security settings | [Compliance checks](guides/compliance-checks.md) |
| Something didn't work | [Troubleshooting](guides/troubleshooting.md) |
| Remove it | [Leave and uninstall](guides/leave-and-uninstall.md) |
