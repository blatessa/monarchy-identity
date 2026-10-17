# Contributing

Contributor and agent guidance lives in [AGENTS.md](AGENTS.md) (rules, layout, conventions),
[docs/dev/testing.md](docs/dev/testing.md) (the lab) and [docs/dev/architecture.md](docs/dev/architecture.md).

- **Never test PAM/sssd/SDDM changes on your own laptop.** Use the lab in `test/`.
- Run `test/run-all.sh` before sending a change (about 15 minutes). Unit tests in `test/unit/` need nothing.
- PAM additions must be safe when `pam_sss.so` is missing, idempotent, and removable with `lib/pamedit.py remove`. Add a test.
- Keep to the scope in [docs/dev/architecture.md](docs/dev/architecture.md#scope): authentication only.
- Update the docs (`docs/`) with behaviour changes and `docs/dev/findings.md` with lessons.

By contributing you agree your work is released under the MIT license in [LICENSE](LICENSE).
