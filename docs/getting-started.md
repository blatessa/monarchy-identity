# Getting started

By the end of this page one Omarchy laptop is connected to your directory, and a person from the directory can sign in
on it. Try it on a spare laptop or a virtual machine first.

The steps are the same for every directory; what you prepare and the options you pass depend on its
[provider](providers/index.md). This walkthrough uses **Active Directory**, the provider available today, with the
example values `CORP.EXAMPLE.COM` (the domain), `joinuser` (an account that may join computers), `laptop-users` (the
group allowed to sign in) and `alice` (a member of it). Replace them with yours.

## 1. Prepare the directory

You need **a group of people who may sign in**, here `laptop-users`, with `alice` in it. Nobody can sign in unless
they are in a group you name. Whatever else the provider needs is on its page; for Active Directory that's an account
that may join computers (`joinuser`) and a few checks on the laptop:
[Active Directory: prepare](providers/ad.md#prepare-the-directory).

## 2. Check the laptop

```bash
timedatectl                 # "System clock synchronized: yes"
```

Plus the provider's own checks. For Active Directory: a unique hostname of at most 15 characters, and DNS that finds
the domain controllers:

```bash
dig -t SRV _ldap._tcp.corp.example.com    # lists your domain controllers
```

If that lists nothing, the laptop is asking a DNS server that doesn't know your domain. Usually the office network or
VPN fixes this; on a test network, see [Active Directory: prepare the laptops](providers/ad.md#prepare-the-laptops).

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
sudo monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser --groups laptop-users
```

`ad` names the provider and `--realm` and `--admin` are its options; `--groups` says who may sign in, whatever the
directory. `sudo` asks for your own laptop password; then `enroll` asks for **`joinuser`'s directory password**. It checks that the directory has the `laptop-users` group, connects the
laptop and turns on directory sign-in. It finishes with `enrolled in CORP.EXAMPLE.COM`.

Enrolling also turns off Omarchy's automatic sign-in at boot, so the login screen appears and people sign in as
themselves. Add `--keep-autologin` to keep it.

## 5. Sign in as a directory user

Keep a terminal open as your own local account while you test, so you can always get back in.

Lock the screen, or open a text console with **Ctrl+Alt+F3**, and sign in as `alice` with **her own directory
password**. The first sign-in takes a few seconds while her home folder is created. After a reboot the login screen has
a username box. Don't test with `su alice`: on Arch, `su` never asks the directory, so it fails even when sign-in works.

Someone who isn't in `laptop-users` is refused. Your own local account works as before, with its own password.

```bash
monarchy-identity status
```

```text
enrolled:        true
provider:        ad
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
