# Signing in to your work laptop

Your laptop uses your **company account**, the same username and password you use for email and other work
systems. This guide covers everyday use. It is for people using the laptop; IT administrators should read
[../ADMIN.md](../ADMIN.md).

> **Short version:** type your company username, press Enter, type your password, press Enter. If something goes
> wrong, jump to [When something goes wrong](#when-something-goes-wrong).

## Signing in

The login screen has two boxes: your **username** on top and your **password** below.

![The Omarchy login screen with a username box above the password box](img/login-screen.png)

1. Type your company username. Use the short form (for example `alice`), unless IT told you otherwise.
2. Press **Enter** to move to the password box.
3. Type your password (you will see dots) and press **Enter**.

**The first time** you sign in on a laptop it takes a few seconds longer, because your personal folder is created.

**Next time,** the screen remembers who signed in last and fills in the username, so you only type your password.
To sign in as someone else, press **Shift+Tab** (or click the username box), type the other username, then continue
as above.

## If the boxes turn red

![The login screen after a failed attempt: both boxes are red](img/login-failed.png)

The boxes turn red when a sign-in did not work. Your username stays in place so you can fix it. The screen does
**not** say why, on purpose. Common causes:

- a typo in the username or password, or **Caps Lock** is on;
- the account is **not allowed on this laptop** (IT decides which accounts can sign in to which laptops);
- the account is **temporarily locked** after too many wrong passwords (see below);
- the laptop can't reach the company network and has never seen you before (see [Working offline](#working-offline)).

**Too many wrong passwords:** after 10 failed attempts in a row the laptop refuses further attempts for about
**2 minutes**. Wait, then try again. Your company account may also have its own, separate lockout rules.

## Locking and unlocking

When you lock the screen (or it locks itself while you are away), unlock it with the same company password.

## Working offline

You can sign in **without** being on the office network or VPN, as long as you have **signed in on this laptop
before while it was connected**. The laptop remembers a protected copy of your credentials for this.

- The **first** sign-in on a laptop needs the company network.
- While offline, the password that works is the one you last used on this laptop while connected.
- If you change your password somewhere else, connect the laptop to the company network and sign in once so it
  learns the new one.
- Your company may require you to reconnect after a number of days away. If sign-in stops working after a long
  trip, connect to the company network and try again.

## Changing your password

1. Open a terminal (in Omarchy: **Super + Enter**).
2. Type `passwd` and press Enter.
3. Enter your **current** password, then your **new** password twice.

Your company sets the rules for a good password (length, complexity, how often you must change it). If the new one
is rejected, the message will say why.

**If you are told your password has expired or must be changed:** the graphical login screen cannot ask you for a
new password; it simply fails. Do one of these instead:

- change it first in the company's web portal (if you have one) and then sign in; or
- press **Ctrl+Alt+F3** for a text login and sign in there; you should be asked to set a new password (press
  **Ctrl+Alt+F1** or **F2** to get back to the graphical screen). If it just says the login failed, use one of the
  other options; or
- ask IT to help.

## Admin rights

Signing in does **not** make you an administrator. If IT gave you admin rights, commands that start with `sudo`
work and ask for your company password. If `sudo` says you are not allowed, you don't have admin rights on this
laptop. Ask IT if you think you should.

## Checking that everything is set up

Open a terminal and run:

    monarchy-identity status

It only reads information (no admin rights needed) and shows whether the laptop is joined to the company
directory, which sign-in rule applies, whether disk encryption and the firewall are on, and so on. This is also
exactly what IT's compliance checks look at; nothing in it contains your files, browsing or messages.

## When something goes wrong

| What you see | Likely cause | What to do |
|---|---|---|
| Red boxes right after typing a password | Typo, Caps Lock, wrong username | Retype carefully; check Caps Lock |
| Red boxes, you are sure the password is right | Account not allowed on this laptop, or locked | Wait 2 minutes and retry once; then contact IT |
| Worked yesterday, fails today, you were away | Offline too long, or password changed elsewhere | Connect to the company network, then sign in |
| "New token required" / told to change password | Password expired | See [Changing your password](#changing-your-password) |
| Screen is black with only a cursor | Display problem, not the sign-in | Restart the laptop; if it repeats, tell IT |
| `sudo` says "not in the sudoers file" | You don't have admin rights | Ask IT if you need them |
| `monarchy-identity status` says `enrolled: false` | Laptop not joined to the company directory | Contact IT |

## Contacting IT

Please include:

- your username and roughly **when** it failed;
- what the screen showed (a phone photo of the red boxes is fine);
- the output of `monarchy-identity status`.

**Never send your password**, even to IT; they will never need it.

## What you should not do

- Don't edit files under `/etc` that mention `monarchy`, and don't remove the `monarchy-identity` package. The
  laptop repairs these settings automatically, and changing them can lock you (and IT) out.
- Don't share your account with anyone on the laptop. Each person signs in with their own username.

See also: [Quick reference](QUICK-REFERENCE.md).
