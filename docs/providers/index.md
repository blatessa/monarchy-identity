# Providers

A provider is the directory-specific part of monarchy-identity: a directory of executables under
`providers/<name>/` that the core CLI dispatches to.

| Provider | State | Notes |
|---|---|---|
| [`sssd`](sssd.md) | Implemented | Active Directory and Samba AD, via `net ads join` and sssd. |
| `local` | Built in | Not enrolled. Every action is a no-op; `policy` fails. |
| FreeIPA / generic LDAP + Kerberos | Planned | Would reuse most of the sssd provider. |
| OIDC (Entra ID, Okta, Google) | Planned | Undecided: candidate packages may require the AUR, which this project avoids. |

`monarchy-identity providers` lists what is installed. To add one, see [Writing a provider](writing-a-provider.md).
