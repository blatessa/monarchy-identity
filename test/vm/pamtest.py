#!/usr/bin/env python3
"""pamtest.py SERVICE USER PASSWORD  - run authenticate + acct_mgmt via libpam (no pamtester on Arch)."""
import ctypes, ctypes.util, sys
newpw=None
argv=sys.argv[1:]
if "--chauthtok" in argv:
    i=argv.index("--chauthtok"); newpw=argv[i+1]; del argv[i:i+2]
args=[a for a in argv if a!="--session"]; want_session="--session" in argv
svc, user, pw = args[:3]
libpam = ctypes.CDLL(ctypes.util.find_library("pam")); libc = ctypes.CDLL(ctypes.util.find_library("c"))
class Msg(ctypes.Structure): _fields_ = [("style", ctypes.c_int), ("msg", ctypes.c_char_p)]
class Resp(ctypes.Structure): _fields_ = [("resp", ctypes.c_char_p), ("retcode", ctypes.c_int)]
CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(Msg)),
                        ctypes.POINTER(ctypes.POINTER(Resp)), ctypes.c_void_p)
libc.calloc.restype = ctypes.c_void_p; libc.strdup.restype = ctypes.c_void_p
def conv(n, msgs, resp, _):
    arr = libc.calloc(n, ctypes.sizeof(Resp)); resp[0] = ctypes.cast(arr, ctypes.POINTER(Resp))
    for i in range(n):
        if msgs[i].contents.style in (1, 2):  # PROMPT_ECHO_OFF / ON
            text = (msgs[i].contents.msg or b"").lower()
            val = newpw if (newpw and (b"new" in text or b"retype" in text or b"reenter" in text)) else pw
            resp[0][i].resp = ctypes.cast(libc.strdup(val.encode()), ctypes.c_char_p)
    return 0
class Conv(ctypes.Structure): _fields_ = [("conv", CONV), ("data", ctypes.c_void_p)]
c = Conv(CONV(conv), None); h = ctypes.c_void_p()
libpam.pam_start.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(Conv), ctypes.POINTER(ctypes.c_void_p)]
libpam.pam_strerror.restype = ctypes.c_char_p
assert libpam.pam_start(svc.encode(), user.encode(), ctypes.byref(c), ctypes.byref(h)) == 0
for name in (() if newpw else ("pam_authenticate", "pam_acct_mgmt")):
    rc = getattr(libpam, name)(h, 0)
    if rc: print(f"DENIED {svc}/{user}: {name}: {libpam.pam_strerror(h, rc).decode()}"); sys.exit(1)
if newpw:
    rc = libpam.pam_chauthtok(h, 0)
    if rc: print(f"DENIED {svc}/{user}: pam_chauthtok: {libpam.pam_strerror(h, rc).decode()}"); sys.exit(1)
    print(f"PASSWORD-CHANGED {svc}/{user}"); sys.exit(0)
if want_session:
    libpam.pam_setcred(h, 2)   # PAM_ESTABLISH_CRED
    rc = libpam.pam_open_session(h, 0)
    if rc: print(f"DENIED {svc}/{user}: pam_open_session: {libpam.pam_strerror(h, rc).decode()}"); sys.exit(1)
    libpam.pam_close_session(h, 0)
print(f"ALLOWED {svc}/{user}")
