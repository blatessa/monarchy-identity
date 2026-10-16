#!/usr/bin/env python3
"""qmon.py - drive the test VM through the QEMU HMP monitor socket.
  qmon.py shot OUT.png            screenshot of the VM display (PNG)
  qmon.py type 'text'             type text with sendkey (handles shift/symbols)
  qmon.py key NAME [NAME...]      send named keys (ret, tab, backspace, ...)
"""
import os, socket, struct, sys, tempfile, time, zlib

SOCK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "images", "monitor.sock")
SHIFT = {c: k for c, k in zip('!@#$%^&*()', '1234567890')}
SYMS = {' ': 'spc', '-': 'minus', '=': 'equal', '[': 'bracket_left', ']': 'bracket_right', ';': 'semicolon',
        "'": 'apostrophe', ',': 'comma', '.': 'dot', '/': 'slash', '\\': 'backslash', '`': 'grave_accent',
        '_': 'shift-minus', '+': 'shift-equal', '{': 'shift-bracket_left', '}': 'shift-bracket_right',
        ':': 'shift-semicolon', '"': 'shift-apostrophe', '<': 'shift-comma', '>': 'shift-dot',
        '?': 'shift-slash', '|': 'shift-backslash', '~': 'shift-grave_accent'}

def hmp(cmd, wait=0.15):
    s = socket.socket(socket.AF_UNIX); s.connect(SOCK); s.settimeout(3)
    try: s.recv(4096)
    except OSError: pass
    s.sendall(cmd.encode() + b"\n"); time.sleep(wait)
    try: out = s.recv(65536)
    except OSError: out = b""
    s.close(); return out.decode(errors="replace")

def keyname(c):
    if c.isalpha(): return ("shift-" + c.lower()) if c.isupper() else c
    if c.isdigit(): return c
    if c in SHIFT: return "shift-" + SHIFT[c]
    if c in SYMS: return SYMS[c]
    raise SystemExit(f"cannot type {c!r}")

def ppm_to_png(ppm, png):
    d = open(ppm, "rb").read()
    parts = d.split(b"\n", 3)             # P6 / w h / maxval / data
    w, h = map(int, parts[1].split()); data = parts[3]
    raw = b"".join(b"\x00" + data[y*w*3:(y+1)*w*3] for y in range(h))
    def chunk(t, b): c = struct.pack(">I", len(b)) + t + b; return c + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
    open(png, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) +
                          chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))

def main():
    a = sys.argv[1:]
    if not a: sys.exit(__doc__)
    if a[0] == "shot":
        ppm = tempfile.mktemp(suffix=".ppm"); hmp(f"screendump {ppm}", 0.8)
        ppm_to_png(ppm, a[1]); os.unlink(ppm)
    elif a[0] == "type":
        for c in a[1]: hmp(f"sendkey {keyname(c)}", 0.06)
    elif a[0] == "key":
        for k in a[1:]: hmp(f"sendkey {k}", 0.1)
    else: sys.exit(__doc__)
main()
