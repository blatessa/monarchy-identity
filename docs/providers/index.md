# Providers

A provider connects monarchy-identity to one kind of directory.

| Provider | Directory | State |
|---|---|---|
| [`sssd`](sssd.md) | Active Directory, Samba AD | Available (the default) |
| FreeIPA / LDAP + Kerberos | | Planned |
| OIDC | Entra ID, Okta, Google Workspace | Under consideration |

`monarchy-identity providers` lists what's installed. Adding a provider is covered in the developer docs:
[Writing a provider](../dev/writing-a-provider.md).
