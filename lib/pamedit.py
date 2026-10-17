#!/usr/bin/env python3
"""Idempotently add/remove pam_sss (+ mkhomedir) in an Omarchy PAM service file.

usage: pamedit.py apply|remove|check FILE

Design (see docs/dev/DESIGN.md): local users must keep working untouched, so pam_sss is tried FIRST
and ignored for users it does not know ("default=ignore"); on success it skips the rest of the
auth stack (pam_unix + faillock authfail) with a skip count computed from the real file, which
keeps it correct next to Omarchy's pam_systemd_home skip lines.
Every inserted block is wrapped in BEGIN/END markers so `remove` is exact.

SAFETY (learned the hard way): if pam_sss.so is missing or sssd is down, authentication for LOCAL users must be
unaffected. Every rule is "-"-prefixed (silent when the module can't load) and the account rule maps
user_unknown / authinfo_unavail / module_unknown to ignore. Only a real answer from pam_sss (denied, expired,
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


def apply(lines):
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
        lines[first:first] = block(
            f"-auth      [success={skip} default=ignore]  pam_sss.so forward_pass")
    # --- account: before first of (pam_systemd_home | pam_unix) account rule
    first = None
    for pat in (r"pam_systemd_home\.so", r"pam_unix\.so"):
        i = find(lines, "account", pat)
        if i is not None and (first is None or i < first):
            first = i
    u = find(lines, "account", r"pam_unix\.so")
    if first is not None and u is not None:
        skip = count_rules(lines, "account", first, u)
        lines[first:first] = block(
            f"-account   [success={skip} user_unknown=ignore authinfo_unavail=ignore module_unknown=ignore default=bad]  pam_sss.so")
    # --- password: same pattern as auth (pam_sss first; unknown/local users are ignored and fall through)
    first = None
    for pat in (r"pam_systemd_home\.so", r"pam_unix\.so"):
        i = find(lines, "password", pat)
        if i is not None and (first is None or i < first):
            first = i
    u = find(lines, "password", r"pam_unix\.so")
    if first is not None and u is not None:
        skip = count_rules(lines, "password", first, u)
        lines[first:first] = block(
            f"-password  [success={skip} default=ignore]  pam_sss.so")
    # --- session: at the top of the session block
    s = None
    for i, ln in enumerate(lines):
        if is_rule(ln, "session"):
            s = i
            break
    if s is not None and find(lines, "session", r"pam_unix\.so") is not None:
        lines[s:s] = [BEGIN + "\n",
                      "session    required   pam_mkhomedir.so umask=0077\n",
                      "-session   optional   pam_sss.so\n",
                      END + "\n"]
    return lines


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("apply", "remove", "check"):
        sys.exit(__doc__)
    mode, path = sys.argv[1], sys.argv[2]
    with open(path) as f:
        lines = f.readlines()
    if mode == "check":
        sys.exit(0 if any(ln.strip() == BEGIN for ln in lines) else 1)
    new = apply(lines) if mode == "apply" else strip_blocks(lines)
    if new != lines:
        tmp = path + ".oi-tmp"
        with open(tmp, "w") as f:
            f.writelines(new)
        import os, shutil
        shutil.copymode(path, tmp)
        os.replace(tmp, path)


if __name__ == "__main__":
    main()
