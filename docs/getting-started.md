# Getting started

By the end of this page one Omarchy laptop is connected to your directory, and a person from the directory can sign in
on it. Try it on a spare laptop or a virtual machine first.

This walkthrough uses **Active Directory** with the example values `CORP.EXAMPLE.COM` (the domain), `joinuser` (an
account that may join computers), `laptop-users` (the group allowed to sign in) and `alice` (a member of it). Replace
them with yours.

## 1. Prepare

In the directory you need the `laptop-users` group with `alice` in it, and the `joinuser` account. On the laptop, a
unique short hostname, a correct clock, and DNS that finds the domain controllers. All of it, with the commands to
check: [Active Directory: prepare](providers/ad.md#prepare-the-directory).

## 2. Install

```bash
sudo pacman -S monarchy-identity
```

Until the package reaches Omarchy's package repository, download the `.pkg.tar.zst` file and `SHA256SUMS` from the
[releases page](https://github.com/blatessa/monarchy-identity/releases) instead, then:

```bash
sha256sum -c --ignore-missing SHA256SUMS
sudo pacman -U monarchy-identity-*.pkg.tar.zst
```

Installing changes nothing until you enroll.

## 3. Enroll

```bash
sudo monarchy-identity enroll ad --realm CORP.EXAMPLE.COM --admin joinuser --groups laptop-users
```

`sudo` asks for your own laptop password; then `enroll` asks for **`joinuser`'s directory password**. It checks that
the directory has the `laptop-users` group, connects the laptop and turns on directory sign-in, and finishes with
`enrolled in CORP.EXAMPLE.COM`. It also turns off Omarchy's automatic sign-in at boot, so the login screen appears
(`--keep-autologin` keeps it).

## 4. Sign in as a directory user

Keep a terminal open as your own local account while you test, so you can always get back in.

Lock the screen, or open a text console with **Ctrl+Alt+F3**, and sign in as `alice` with **her own directory
password**. The first sign-in takes a few seconds while her home folder is created. After a reboot the login screen has
a username box. Don't test with `su alice`: on Arch, `su` never asks the directory, so it fails even when sign-in works.

Someone who isn't in `laptop-users` is refused. Your local account works as before, with its own password.

```bash
monarchy-identity status
```

## What now

| You want to | Read |
|---|---|
| Do this for many laptops | [Roll out to a fleet](guides/rollout.md), then [Automate enrollment](guides/automation.md) |
| Change who may sign in, or undo it | [Manage enrolled laptops](guides/manage.md) |
| Something didn't work | [Troubleshooting](guides/troubleshooting.md) |
