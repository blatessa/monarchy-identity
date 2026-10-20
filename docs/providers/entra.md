# Microsoft Entra ID

!!! note "In development"
    Entra ID works in our lab against a test tenant, and needs the Entra client package (`himmelblau`), which isn't
    in Omarchy's package repository yet. See [Status and limits](../status.md#entra-id-in-development).

The `entra` provider connects laptops to Microsoft Entra ID (formerly Azure AD). People sign in with their Microsoft
work account. Each laptop **joins the tenant** as a device the first time someone signs in on it.

```bash
sudo monarchy-identity enroll entra --tenant corp.onmicrosoft.com --client-id 0f1e2d3c-... --groups linux-users
```

`--tenant` is the tenant's domain: its `onmicrosoft.com` name or a domain you've verified in it. `--client-id`
identifies an **app registration** that lets `enroll` look up group names. Its **client secret** is asked for while
enrolling and never stored.

## Prepare the tenant

You need an Entra administrator for these, in the [Microsoft Entra admin center](https://entra.microsoft.com):

1. **A group** of the people allowed on these laptops (`linux-users`), and optionally one for `sudo` (`linux-admins`).
   Security groups, with names unique in the tenant.
2. **An app registration** so `enroll` can turn group names into Entra's ids:
    - **Applications > App registrations > New registration.** Any name, "Accounts in this organizational directory
      only", and no redirect URI.
    - **API permissions > Add a permission > Microsoft Graph > Application permissions.** Add `Group.Read.All` and
      `User.Read.All`, then **Grant admin consent**.
    - **Certificates & secrets > New client secret.** Copy its **Value**: that's the secret `enroll` asks for.
    - From **Overview**, copy the **Application (client) ID**: that's `--client-id`.
    - The secret is used only while enrolling, and when `policy set` names a group the laptop hasn't looked up
      before. Laptops keep working after it expires.
3. **Devices may join.** Under **Devices > Device settings**, "Users may join devices to Microsoft Entra" must include
   the people who sign in first on each laptop (All, or a group with them in it). Each laptop counts towards that
   person's "Maximum number of devices per user".

Multi-factor authentication needs nothing extra. Whatever your tenant already asks of people (approving on their phone,
or a code from an authenticator app) is asked at the login screen; see [How it behaves](#how-it-behaves).

## Prepare the laptops

- **The Entra client:** `sudo pacman -S himmelblau`. Until it reaches Omarchy's package repository, install the
  package file you were given with `sudo pacman -U`.
- **Internet access to Microsoft** while enrolling and for each person's first sign-in: HTTPS to
  `login.microsoftonline.com`, `graph.microsoft.com` and `enterpriseregistration.windows.net`.
- **A correct clock.** `timedatectl` should say "System clock synchronized: yes".
- **A recognisable hostname.** It becomes the device's name in Entra, which allows duplicate names, so a unique one
  (`laptop-0042`) makes the device easy to find.

## Enroll options

| Option | Default | Description |
|---|---|---|
| `--tenant DOMAIN` | required | The tenant: `corp.onmicrosoft.com`, or a domain verified in it. |
| `--client-id ID` | required with `--groups` | The app registration's Application (client) ID. Optional with `--users`; with it, the names are checked. |
| `--password-file FILE` | standard input | File holding the client secret; readable only by its owner. Also `MONARCHY_IDENTITY_PASSWORD_FILE`. |

The options every provider shares (who may sign in, `sudo`, autologin) are in the
[CLI reference](../reference/cli.md#enroll). `--offline-days` is refused: Entra's client has no limit on how long
offline sign-in works.

`--users` takes sign-in names (`alice@corp.example.com`); a bare `alice` gets the tenant's domain. Before it changes
anything, `enroll` checks that the tenant exists and, with `--client-id`, that the secret works and that every group
and user exists (and that no two groups share a name). If it stops partway, run the same command again.

## How it behaves

- **Sign-in names.** People can type their short name (`alice`) or their full sign-in name
  (`alice@corp.example.com`). They get the same user ID on every laptop.
- **The first sign-in on a laptop needs the internet.** The first person to sign in joins the laptop to the tenant as
  a device.
- **Multi-factor authentication** is asked at a person's first sign-in on each laptop, and whenever Entra wants it
  again. After that the laptop remembers them, and the login screen, lock screen and `sudo` take the password alone.
  At the login screen:
    - **Approval on the phone:** after the password, the login screen shows the number to enter in the Authenticator
      app. Approve, and the desktop starts. Microsoft uses this whenever a person has the Authenticator app set up
      for it, even if they chose codes as their default.
    - **A code:** after the password, a code line appears under it. Type the code from the authenticator app and
      press Enter.
    - **A mistyped password or code** is one try: the login screen never repeats it to Microsoft.
- **`ssh`** refuses people who have only a password; people with multi-factor authentication give their code each
  time.
- **Offline**, people who have signed in on the laptop before can sign in with the password they last used online.
  There's no expiry. Until the laptop is online again, it doesn't learn about a changed password, a disabled account
  or a removed group membership. Someone who has never signed in on the laptop can't sign in offline.
- **A password Entra says must be changed** (it expired, or you reset it with "change at next sign-in"): at the
  login screen, after the password, two lines appear for the new one. Type it twice and press Enter: the password is
  changed in Entra and the desktop starts. Entra's password rules apply, and its message says why a password isn't
  taken. People with multi-factor authentication give a code first, as Entra asks for it before the change, and a
  fresh one after it, as they're signed in again with the new password.
- **Any other password change** is made with Microsoft (for example at <https://myaccount.microsoft.com>), not with
  `passwd` on the laptop.
- **`sudo`** for `--sudo-groups` works by group name, as with every provider.
- **Leaving** keeps the device in Entra. `leave` prints its device ID: delete it under **Devices** in the admin
  center. A reinstalled laptop joins as a new device with the same name, next to the old one.
- **Another tenant:** a laptop enrolled in one tenant must `leave` before enrolling in another. Enrolling again in the
  same tenant keeps the device.

## Troubleshooting

| `enroll` says | What to do |
|---|---|
| `the Entra ID client (himmelblau) is not installed` | Install it: [Prepare the laptops](#prepare-the-laptops). |
| `Entra has no tenant named ...` | Check `--tenant`: the `onmicrosoft.com` name or a verified domain. |
| `cannot reach Entra ID` | The laptop can't reach Microsoft: network, proxy or firewall. |
| `--client-id is required to look up the groups` | Pass the app registration's ID: [Prepare the tenant](#prepare-the-tenant). |
| `the tenant has no app registration with client id ...` | Use the **Application (client) ID**, not the Object ID or the secret's ID. |
| `the client secret is wrong`, `has expired` or `is not valid yet` | Create a new client secret and use its **Value**. |
| `the app registration may not read the directory` | Add `Group.Read.All` and `User.Read.All` as application permissions, and grant admin consent. |
| `Entra has no group or user named: ...` | Check the names; users need their full sign-in name, or a bare name in the tenant's domain. |
| `more than one Entra group is named: ...` | Rename one of them: sign-in can't tell them apart. |
| `Entra ID can't limit how long offline sign-in works` | Leave out `--offline-days`. |
| `already enrolled in '...'` | Enrolled in another tenant: `leave` first. |
| `the himmelblau daemon did not come up` | Run the same command again; if it repeats, `journalctl -u himmelblaud` says why. |

| Someone | What to do |
|---|---|
| Can't sign in on a laptop for the first time | It needs the internet, and they must be in an allowed group. Check that devices may join (see [Prepare the tenant](#prepare-the-tenant)). |
| Sees a number on the login screen | Enter it in the Microsoft Authenticator app on their phone. |
| Is refused by `ssh` with the right password | Expected for people without multi-factor authentication. |
| Signed in offline with an old password | The laptop learns the new one at the next online sign-in. |
| Sees "Failed to change user password" at the login screen | The rest of the message says why: usually Entra's password rules. They type another new password. |

## Status details

`status --json` reports these under `details`, each `"true"` when healthy:

| Key | Means |
|---|---|
| `himmelblaud_active` | The Entra client is running. |
| `nss_himmelblau` | The laptop looks people up in Entra. |
| `entra_reachable` | The Entra client can reach Microsoft. |
| `pam_system_auth`, `pam_omarchy_lock_password` | Sign-in and the lock screen use Entra. |
| `pam_sddm` | The login screen asks Entra once per try, and shows the code line or the number to approve. |
