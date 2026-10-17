# Getting started

By the end of this page one Omarchy laptop is joined to your Active Directory domain, and a directory user can sign in
on it. Try it on a spare laptop or a virtual machine first.

The example values below are `CORP.EXAMPLE.COM` (your domain), `joinuser` (an account that may join computers),
`laptop-users` (the group allowed to sign in) and `alice` (a member of that group). Replace them with yours.

## 1. Prepare the directory

You need two things in the directory:

1. **A group of people who may sign in**, here `laptop-users`, with `alice` in it. Nobody can sign in unless they are
   in a group you name.
2. **An account that may join computers**, here `joinuser`. For a first test, an existing administrator account is fine.

On Samba AD:

```bash
samba-tool group add laptop-users
samba-tool group addmembers laptop-users alice
```

On Windows AD (not yet tested with this tool), in PowerShell: `New-ADGroup laptop-users -GroupScope Global` and
`Add-ADGroupMember laptop-users alice`.

## 2. Check the laptop

```bash
hostnamectl hostname        # unique, at most 15 characters, not "omarchy" or "archlinux"
timedatectl                 # "System clock synchronized: yes"
dig -t SRV _ldap._tcp.corp.example.com   # the laptop can find your domain controllers
```

The hostname becomes the laptop's name in the directory. To change it: `sudo hostnamectl set-hostname laptop-0042`.

## 3. Install

Download the `.pkg.tar.zst` files and `SHA256SUMS` from the
[releases page](https://github.com/blatessa/monarchy-identity/releases), then:

```bash
sha256sum -c --ignore-missing SHA256SUMS
sudo pacman -U monarchy-identity-*.pkg.tar.zst
```

Installing changes nothing until you enroll.

## 4. Enroll

```bash
sudo monarchy-identity enroll --realm CORP.EXAMPLE.COM --admin joinuser --groups laptop-users
```

It asks for `joinuser`'s password, checks that the directory has the `laptop-users` group, joins the domain and turns on
directory sign-in. It finishes with `enrolled in CORP.EXAMPLE.COM`.

Enrolling also turns off Omarchy's automatic sign-in at boot, so the login screen appears and people sign in as
themselves. Add `--keep-autologin` to keep it.

## 5. Sign in as a directory user

Lock the screen, or open a text console with **Ctrl+Alt+F3**, and sign in as `alice` with her directory password. The
first sign-in takes a few seconds while her home folder is created. After a reboot the login screen has a username box.

Someone who isn't in `laptop-users` is refused. Your own local account works as before.

```bash
monarchy-identity status
```

```text
enrolled:        true
provider:        sssd
login mode:      groups
autologin:       false
```

## What now

| You want to | Read |
|---|---|
| Do this for many laptops | [Roll out to a fleet](guides/rollout.md), then [Automate enrollment](guides/automation.md) |
| Change who may sign in | [Change who may sign in](guides/change-policy.md) |
| Something didn't work | [Troubleshooting](guides/troubleshooting.md) |
| Undo it | [Leave and uninstall](guides/leave-and-uninstall.md) |
