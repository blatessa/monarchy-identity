# Contributing

Start with [CLAUDE.md](CLAUDE.md): it has the hard rules, repo layout, provider contract and the dev loop (it is
written for coding agents but is the accurate contributor guide too).

The short version:

- **Never test PAM/sssd/SDDM changes on your own laptop.** Use the lab in `test/` (a throwaway Samba AD in Docker and
  an Arch VM under QEMU/KVM). A bad PAM edit locks you out; we have bricked the test VM that way on purpose.
- Run `test/run-all.sh` before sending a change (about 16 minutes). Unit tests in `test/unit/` need nothing.
- Anything we add to a PAM stack must be safe when `pam_sss.so` is missing, must be idempotent, and must come out
  exactly with `lib/pamedit.py remove`. Add a test.
- Failure must leave the machine as it was found.
- Update `docs/` (admin and user docs) with behaviour changes, and `TODO.md` / `HANDOFF.md` with what you learned.

By contributing you agree your work is released under the MIT license in [LICENSE](LICENSE).
