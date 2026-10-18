#!/usr/bin/env python3
"""adminprompt.py IDENTITY PASSWORD - answer a real polkit admin prompt (pkexec under pkttyagent) as IDENTITY.

Prints AUTHORIZED, REFUSED, or NOT-OFFERED (IDENTITY isn't among the admins polkit offers). Goes through polkitd and
its socket-activated, sandboxed agent helper, as Omarchy's graphical prompt does. pkexec's built-in agent can't: it runs
setuid, so the helper answers polkitd for uid 0 and gets "No session for cookie" (docs/dev/findings.md)."""
import os, pty, select, signal, sys, time
ident, pw = sys.argv[1].encode(), sys.argv[2].encode()
pid, fd = pty.fork()
if pid == 0:   # pkexec asks on behalf of its parent, so this process registers the agent and stays pkexec's parent
    r, w = os.pipe()
    if os.fork() == 0:
        os.close(r)
        os.execvp("pkttyagent", ["pkttyagent", "--process", str(os.getppid()), "--notify-fd", str(w)])
    os.close(w); os.read(r, 1)   # closed once the agent is registered for this process
    if (child := os.fork()) == 0: os.execvp("pkexec", ["pkexec", "--disable-internal-agent", "/usr/bin/true"])
    os._exit(os.waitstatus_to_exitcode(os.waitpid(child, 0)[1]))
buf, verdict, end = b"", None, time.time() + 30
while time.time() < end:
    if not select.select([fd], [], [], 1)[0]: continue
    try: chunk = os.read(fd, 4096)
    except OSError: break
    if not chunk: break
    buf += chunk; last = buf.rstrip().splitlines()[-1] if buf.strip() else b""
    if last.startswith(b"Choose identity"):
        n = [l.split(b".")[0].strip() for l in buf.splitlines() if l.split() and l.split()[-1] == ident]
        if not n: verdict = "NOT-OFFERED"; break
        os.write(fd, n[-1] + b"\n"); buf += b"\n"
    elif last.endswith(b"Password:"):
        if b"Authenticating as: " in buf and buf.split(b"Authenticating as: ")[-1].split()[0] != ident:
            verdict = "NOT-OFFERED"; break   # a single admin, someone else
        os.write(fd, pw + b"\n"); buf += b"\n"
done, st = os.waitpid(pid, os.WNOHANG)
if not done: os.kill(pid, signal.SIGKILL); _, st = os.waitpid(pid, 0)
try: os.killpg(pid, signal.SIGTERM)   # the agent
except ProcessLookupError: pass
if verdict is None: verdict = "AUTHORIZED" if os.waitstatus_to_exitcode(st) == 0 else "REFUSED"
tail = " | ".join(l.strip() for l in buf.decode(errors="replace").splitlines() if l.strip() and l.strip() != pw.decode())[-300:]
print(f"{verdict} {ident.decode()}" + ("" if verdict == "AUTHORIZED" else f": {tail}"))
sys.exit(verdict != "AUTHORIZED")
