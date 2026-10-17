# Getting started

By the end of this page one Omarchy laptop is joined to your Active Directory domain, and a directory user can sign in
on it. It takes about 15 minutes. Use a spare laptop or a virtual machine first: this tool edits the login (PAM)
configuration. A safety timer reverts the change if you don't confirm it, and you keep a local account that always works.

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
getent hosts corp.example.com   # the laptop's DNS must resolve your domain
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
sudo monarchy-identity enroll sssd \
  --realm CORP.EXAMPLE.COM --admin joinuser \
  --mode groups --groups laptop-users \
  --disable-autologin --confirm-within 10
```

It asks for `joinuser`'s password, joins the domain, and configures sign-in. If anything fails, it undoes everything
and removes the computer account it created. When it finishes it prints `enrolled in CORP.EXAMPLE.COM`.

`--confirm-within 10` starts a 10-minute timer. If you do nothing, the laptop **leaves the domain by itself**. That is
your safety net while you test; step 6 cancels it.

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

`enrolled: true` and `login mode: groups` mean it's in place.

## 6. Confirm

When `alice` could sign in and a non-member couldn't, cancel the revert timer:

```bash
sudo monarchy-identity confirm
```

Done: the laptop is enrolled. If something went wrong instead, wait for the timer, or undo it now with
`sudo monarchy-identity leave --admin joinuser`.

## What now

| You want to | Read |
|---|---|
| Do this for many laptops | [Plan a rollout](guides/rollout-planning.md), then [Automate enrollment](guides/automation.md) |
| Change who may sign in later | [Change who may sign in](guides/change-policy.md) |
| Report or check laptop security settings | [Compliance checks](guides/compliance-checks.md) |
| Something didn't work | [Troubleshooting](guides/troubleshooting.md) |
| Remove it | [Leave and uninstall](guides/leave-and-uninstall.md) |
