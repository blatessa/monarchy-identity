#!/usr/bin/env python3
"""Idempotently add/remove a provider's PAM module (+ mkhomedir) in an Omarchy PAM service file.

usage: pamedit.py apply [--no-mkhomedir] [--retry-on-abort] FILE MODULE [TYPE=ARGS ...]    e.g. apply /etc/pam.d/system-auth pam_sss.so auth=forward_pass
       pamedit.py greeter FILE HELPER                   e.g. greeter /etc/pam.d/sddm /usr/share/monarchy-identity/lib/password-expired
       pamedit.py remove|check FILE

The provider names the module and its arguments per stack (TYPE is auth, account, password or session); the rules
around it are fixed here. Design (see docs/dev/architecture.md): local users must keep working untouched, so the
module is tried FIRST and ignored for users it does not know ("default=ignore"); on success it skips the rest of the
auth stack (pam_unix + faillock authfail) with a skip count computed from the real file, which
keeps it correct next to Omarchy's pam_systemd_home skip lines.
Accounts in /etc/passwd skip the module (pam_localuser): the directory never decides for a local account, even one
that shares a name with a directory user (it would deny the owner their own account, or let the directory user in as
it, with its local groups). Local entries already win in nsswitch, so this is the same answer.
Every inserted block is wrapped in BEGIN/END markers so `remove` is exact, whatever module was inserted.

SAFETY (learned the hard way): if the module is missing or its daemon is down, authentication for LOCAL users must be
unaffected. Every rule is "-"-prefixed (silent when the module can't load) and the account rule maps
user_unknown / authinfo_unavail / module_unknown to ignore. Only a real answer from the module (denied, expired,
new token required) may fail a login. With a plain `default=bad` a missing module failed EVERY login, local
users and root included, even sshd.
"""
import re
import sys

BEGIN = "# BEGIN monarchy-identity"
END = "# END monarchy-identity"


def is_rule(line, kind):
    s = line.strip().lstrip("-")
    return bool(s) and not s.startswith("#") and s.split()[0] == kind


def strip_blocks(lines):
    out, skip = [], False
    for ln in lines:
        if ln.strip() == BEGIN:
            skip = True
            continue
        if ln.strip() == END:
            skip = False
            continue
        if not skip:
            out.append(ln)
    return out


def find(lines, kind, pattern, start=0):
    for i in range(start, len(lines)):
        if is_rule(lines[i], kind) and re.search(pattern, lines[i]):
            return i
    return None


def count_rules(lines, kind, a, b):
    return sum(1 for i in range(a, b + 1) if is_rule(lines[i], kind))


def block(rule):
    return [BEGIN + "\n", rule + "\n", END + "\n"]


def guarded(kind, *rules):
    """A block whose rules local accounts skip (pam_localuser succeeds for names in /etc/passwd)."""
    guard = f"-{kind:<9} [success={len(rules)} default=ignore]  pam_localuser.so"
    return [BEGIN + "\n", guard + "\n"] + [r + "\n" for r in rules] + [END + "\n"]


TYPES = ("auth", "account", "password", "session")


def parse_module(argv):
    """MODULE [TYPE=ARGS ...] -> (module, {type: " args" or ""}); refuses anything that could add a PAM line."""
    if not argv or not re.fullmatch(r"pam_[A-Za-z0-9_]+\.so", argv[0]):
        sys.exit("pamedit: expected a PAM module name like pam_sss.so")
    args = dict.fromkeys(TYPES, "")
    for a in argv[1:]:
        t, _, v = a.partition("=")
        if t not in TYPES or not re.fullmatch(r"[A-Za-z0-9_.,:/=@ -]*", v):
            sys.exit(f"pamedit: bad module argument {a!r} (expected TYPE=ARGS, TYPE one of {', '.join(TYPES)})")
        args[t] = " " + " ".join(v.split()) if v.strip() else ""
    return argv[0], args


def apply(lines, module, args, mkhomedir=True, retry=False):
    lines = strip_blocks(lines)
    # --- auth: before the first of (pam_systemd_home | pam_unix) in the auth stack
    first = None
    for pat in (r"pam_systemd_home\.so", r"pam_unix\.so"):
        i = find(lines, "auth", pat)
        if i is not None and (first is None or i < first):
            first = i
    fail = find(lines, "auth", r"pam_faillock\.so\s+authfail")
    if first is not None:
        if fail is None:
            # plain stack: skip just pam_unix
            u = find(lines, "auth", r"pam_unix\.so")
            skip = count_rules(lines, "auth", first, u)
        else:
            skip = count_rules(lines, "auth", first, fail)
        rule = f"-auth      [success={skip} default=ignore]  {module}{args['auth']}"
        if retry:
            # A module that gives up (abort) the first time the directory turns out to be unreachable, and answers
            # from its offline cache when asked again: ask again, once, only after an abort.
            first_try = f"-auth      [success={skip + 1} abort=ignore default=1]  {module}{args['auth']}"
            lines[first:first] = guarded("auth", first_try, rule)
        else:
            lines[first:first] = guarded("auth", rule)
    # --- account: before first of (pam_systemd_home | pam_unix) account rule
    first = None
    for pat in (r"pam_systemd_home\.so", r"pam_unix\.so"):
        i = find(lines, "account", pat)
        if i is not None and (first is None or i < first):
            first = i
    u = find(lines, "account", r"pam_unix\.so")
    if first is not None and u is not None:
        skip = count_rules(lines, "account", first, u)
        lines[first:first] = guarded("account",
            f"-account   [success={skip} user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad]  {module}{args['account']}")
    # --- password: same pattern as auth (the module first; unknown/local users are ignored and fall through)
    first = None
    for pat in (r"pam_systemd_home\.so", r"pam_unix\.so"):
        i = find(lines, "password", pat)
        if i is not None and (first is None or i < first):
            first = i
    u = find(lines, "password", r"pam_unix\.so")
    if first is not None and u is not None:
        skip = count_rules(lines, "password", first, u)
        lines[first:first] = guarded("password",
            f"-password  [success={skip} default=ignore]  {module}{args['password']}")
    # --- session: at the top of the session block
    s = None
    for i, ln in enumerate(lines):
        if is_rule(ln, "session"):
            s = i
            break
    if s is not None and find(lines, "session", r"pam_unix\.so") is not None:
        # pam_mkhomedir unless the provider's module makes home directories itself
        lines[s:s] = [BEGIN + "\n"] + (["session    required   pam_mkhomedir.so umask=0077\n"] if mkhomedir else []) + [
                      "-session   [success=1 default=ignore]  pam_localuser.so\n",
                      f"-session   optional   {module}{args['session']}\n",
                      END + "\n"]
    return lines


def greeter(lines, helper):
    """The login screen's service only: let a person whose password must be changed through, to change it first.

    SDDM never asks for a new password (it has no pam_chauthtok), so a "new password required" answer is just a failed
    sign-in. HELPER, run by pam_exec, re-asks the directory with the password the auth stack just accepted and marks the
    sign-in; the account rule then ends the stack successfully for a marked sign-in only, and the session command shows
    the change-password screen before the desktop. Both rules are ignored if pam_exec or HELPER is missing.
    """
    lines = strip_blocks(lines)
    a = find(lines, "auth", r"^\s*-?auth\s+(include|substack)\s+system-login\b")
    c = next((i for i, ln in enumerate(lines) if is_rule(ln, "account")), None)
    if a is None or c is None:
        return lines
    lines[c:c] = block(f"-account   [success=done default=ignore]  pam_exec.so quiet {helper}")
    lines[a + 1:a + 1] = block(f"-auth      optional  pam_exec.so quiet expose_authtok {helper}")
    return lines


def main():
    opts = set()
    while len(sys.argv) > 2 and sys.argv[2] in ("--no-mkhomedir", "--retry-on-abort"):
        opts.add(sys.argv.pop(2))
    mode = sys.argv[1] if len(sys.argv) > 2 else ""
    if mode not in ("apply", "greeter", "remove", "check") or (mode in ("remove", "check") and len(sys.argv) != 3) \
            or (mode == "greeter" and len(sys.argv) != 4):
        sys.exit(__doc__)
    path = sys.argv[2]
    if mode == "apply":
        module, args = parse_module(sys.argv[3:])
    if mode == "greeter" and not re.fullmatch(r"/[A-Za-z0-9_./-]+", sys.argv[3]):
        sys.exit("pamedit: expected an absolute helper path")
    with open(path) as f:
        lines = f.readlines()
    if mode == "check":
        sys.exit(0 if any(ln.strip() == BEGIN for ln in lines) else 1)
    if mode == "apply":
        new = apply(lines, module, args, "--no-mkhomedir" not in opts, "--retry-on-abort" in opts)
    else:
        new = greeter(lines, sys.argv[3]) if mode == "greeter" else strip_blocks(lines)
    if new != lines:
        tmp = path + ".oi-tmp"
        with open(tmp, "w") as f:
            f.writelines(new)
        import os, shutil
        shutil.copymode(path, tmp)
        os.replace(tmp, path)


if __name__ == "__main__":
    main()
