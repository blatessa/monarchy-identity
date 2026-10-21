# Microsoft Entra ID

!!! note "In development"
    Tested in the lab against a test tenant. Needs the `himmelblau` package, not yet in Omarchy's repository. See
    [Status and limits](../status.md#entra-id-in-development).

The `entra` provider signs people in with their Microsoft work account (himmelblau). The laptop joins the tenant as a
device at the first sign-in.

```bash
sudo monarchy-identity enroll entra --tenant corp.onmicrosoft.com --client-id 0f1e2d3c-... --groups linux-users
```

`--client-id` is an app registration used to look up group names; its client secret is asked for and not stored.

## Prepare the tenant

In the [Entra admin center](https://entra.microsoft.com):

1. A security group of people allowed to sign in (`linux-users`), optionally one for `sudo` (`linux-admins`). Group
   names must be unique in the tenant.
2. An app registration: **App registrations > New registration** (single tenant, no redirect URI). **API permissions >
   Microsoft Graph > Application permissions**: `Group.Read.All`, `User.Read.All`, then **Grant admin consent**.
   **Certificates & secrets > New client secret**: copy the **Value**. The **Application (client) ID** is
   `--client-id`. The secret is only used by `enroll` and by `policy set` with a new group name; laptops keep working
   after it expires.
3. **Devices > Device settings**: "Users may join devices to Microsoft Entra" includes the people who sign in first.
   Each laptop counts towards that person's device limit.

MFA needs no setup: whatever the tenant asks for is asked at the login screen.

## Prepare the laptops

- `sudo pacman -S himmelblau` (until it's in Omarchy's repository: `sudo pacman -U` the package file).
- HTTPS to `login.microsoftonline.com`, `graph.microsoft.com`, `enterpriseregistration.windows.net` while enrolling
  and at each person's first sign-in.
- Clock synchronized (`timedatectl`).
- A unique hostname: it's the device name in Entra, which allows duplicates.

## Enroll options

| Option | Default | |
|---|---|---|
| `--tenant DOMAIN` | required | `corp.onmicrosoft.com` or a verified domain |
| `--client-id ID` | required with `--groups` | The app registration's Application (client) ID; with `--users`, optional (checks the names) |
| `--password-file FILE` | standard input | The client secret, mode 600. Also `MONARCHY_IDENTITY_PASSWORD_FILE`. |

Shared options: [CLI reference](../reference/cli.md#enroll). `--offline-days` is refused (himmelblau has no limit).
`--users` takes sign-in names; a bare `alice` gets the tenant's domain. `enroll` checks the tenant, the secret, and
every group and user (and duplicate group names) before changing anything. If it stops partway, run it again.

## How it behaves

- **Names:** `alice` or `alice@corp.example.com`; the same UID on every laptop.
- **First sign-in on a laptop** needs the internet and joins the laptop to the tenant.
- **MFA** is asked at a person's first sign-in on each laptop and when Entra wants it again; otherwise the login
  screen, lock screen and `sudo` take the password alone. At the login screen:
    - Phone approval: the number to enter in Authenticator is shown; approve and the desktop starts. Entra uses this
      whenever Authenticator push is set up.
    - Code: a code line appears under the password.
    - A wrong password or code is one try; the login screen never repeats it, and shows Entra's reason.
- **`ssh`** refuses password-only users; MFA users give a code every time.
- **Offline:** people who signed in on the laptop before sign in with their last online password, without expiry. The
  laptop doesn't learn about password changes, disabled accounts or group removals until it's online.
- **A password Entra says must be changed** (expired, or reset with "change at next sign-in"):
    - At the laptop's very first sign-in, for someone without MFA: the login screen shows two new-password lines; the
      password is changed in Entra and the desktop starts.
    - Otherwise himmelblau can't change it yet (himmelblau#1888, libhimmelblau#109, unreleased): the login screen says
      to sign in at myaccount.microsoft.com first. They change it there, then sign in with the new one.
- **Other password changes** are made with Microsoft (myaccount.microsoft.com), not `passwd`.
- **`sudo`** for `--sudo-groups` by group name, as with every provider.
- **`leave`** keeps the device in Entra and prints its device ID: delete it under **Devices**. A reinstalled laptop
  joins as a new device of the same name.
- **Another tenant** needs `leave` first; enrolling again in the same tenant keeps the device.

## Troubleshooting

| `enroll` says | Fix |
|---|---|
| `the Entra ID client (himmelblau) is not installed` | Install it ([above](#prepare-the-laptops)). |
| `Entra has no tenant named ...` | Check `--tenant`. |
| `cannot reach Entra ID` | Network, proxy or firewall. |
| `--client-id is required to look up the groups` | Pass the app registration's ID. |
| `the tenant has no app registration with client id ...` | Use the Application (client) ID, not the object ID or the secret ID. |
| `the client secret is wrong`, `has expired`, `is not valid yet` | Create a new secret; use its Value. |
| `the app registration may not read the directory` | Add both application permissions and grant admin consent. |
| `Entra has no group or user named: ...` | Check the names; users need full sign-in names or the tenant's domain. |
| `more than one Entra group is named: ...` | Rename one. |
| `Entra ID can't limit how long offline sign-in works` | Leave out `--offline-days`. |
| `already enrolled in '...'` | `leave` first. |
| `the himmelblau daemon did not come up` | Run it again; then `journalctl -u himmelblaud`. |

| Someone | Fix |
|---|---|
| Can't sign in for the first time | Internet, group membership, and "Users may join devices" ([above](#prepare-the-tenant)). |
| Sees a number at the login screen | Enter it in Microsoft Authenticator. |
| Is told to sign in at myaccount.microsoft.com | Their password must be changed (or Entra wants something else interactively): do it there, then sign in. |
| Refused by `ssh` with the right password | Expected without MFA. |
| Signed in offline with an old password | The laptop learns the new one at the next online sign-in. |

## Status details

`status --json` `details`, each `"true"` when healthy:

| Key | |
|---|---|
| `himmelblaud_active` | The daemon is running |
| `nss_himmelblau` | `himmelblau` is in nsswitch |
| `entra_reachable` | The daemon reaches Microsoft (`aad-tool status`) |
| `pam_system_auth`, `pam_omarchy_lock_password` | Sign-in and the lock screen use Entra |
| `pam_sddm` | The login screen asks Entra once per try and handles codes |
