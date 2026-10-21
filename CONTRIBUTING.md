# Contributing

Rules, layout and conventions: [AGENTS.md](AGENTS.md). The lab: [docs/dev/testing.md](docs/dev/testing.md). Design:
[docs/dev/architecture.md](docs/dev/architecture.md).

- Don't test PAM, sssd, nsswitch or SDDM changes on your own laptop; use the lab in `test/`.
- Run `test/unit/run.sh`, and the lab suites your change touches (`test/run-all.sh` runs them all).
- A PAM edit goes through `lib/pamedit.py`, works when the module is missing, and has a removal test.
- Scope is authentication: [architecture](docs/dev/architecture.md#scope).
- Update `docs/` with behaviour changes and `docs/dev/findings.md` with lessons.

Contributions are released under the MIT license in [LICENSE](LICENSE).
