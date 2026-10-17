# Providers

A provider connects monarchy-identity to one kind of directory. Everything else (who may sign in, `sudo`, offline
sign-in, the login screen, surviving updates) works the same whichever provider you use.

| Directory | Provider | State |
|---|---|---|
| Active Directory, Samba AD | [`ad`](ad.md) | Available |
| Microsoft Entra ID | | Planned |
| Okta | | Planned |
| Google Workspace | | Planned |
| FreeIPA, LDAP + Kerberos | | Planned |

Each provider's page covers what to prepare in the directory and on the laptops, its `enroll` options, and its own
troubleshooting. `monarchy-identity providers` lists what's installed.

Adding a provider is covered in the developer docs: [Writing a provider](../dev/writing-a-provider.md).
