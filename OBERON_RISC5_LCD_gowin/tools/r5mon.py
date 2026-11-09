#!/usr/bin/env python3
# r5mon.py - OBERON_RISC5_FAST: type monitor commands over the serial line and print the answers (for checks
# without PuTTY). Usage: r5mon.py 'd 4000' 'w 100000 12345678' ...   (PuTTY must be closed)
#   --dumpcmp FILE.s ADR  dump the words of the assembled program from the board and list the differences.
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools", "r5"))
import serial  # noqa: E402


def read_until(s, end, timeout):
    buf, t0 = b"", time.time()
    while time.time() - t0 < timeout:
        x = s.read(4096)
        if x:
            buf += x
            if buf.endswith(end):
                return buf.decode("latin-1")
    return None


def cmd(s, line, timeout=5):
    for c in (line + "\r").encode():
        s.write(bytes([c]))
        time.sleep(0.005)
    out = read_until(s, b"r5> ", timeout)
    if out is None:
        return None
    return out.split("\r\n", 1)[1].rsplit("r5> ", 1)[0] if "\r\n" in out else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmds", nargs="*")
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--timeout", type=float, default=5)
    ap.add_argument("--dumpcmp", nargs=2, metavar=("SRC", "ADR"))
    a = ap.parse_args()
    with serial.Serial(a.port, 115200, timeout=0.05) as s:
        q = time.time()
        while time.time() - q < 0.2:
            if s.read(4096):
                q = time.time()
        s.write(b"\r")
        if read_until(s, b"r5> ", 2) is None:
            sys.exit("r5mon: no prompt")
        for c in a.cmds:
            out = cmd(s, c, a.timeout)
            print(f"r5> {c}\n{out if out is not None else '(no answer)'}", end="")
        if a.dumpcmp:
            import r5asm
            words, _, _ = r5asm.assemble(open(a.dumpcmp[0]).read())
            base = int(a.dumpcmp[1], 16)
            bad = 0
            for i in range(0, len(words), 4):
                out = cmd(s, f"d {base + 4 * i:X}") or ""
                got = [int(ln.split(":")[1], 16) for ln in out.split("\r\n") if ":" in ln]
                for j, w in enumerate(words[i:i + 4]):
                    g = got[j] if j < len(got) else None
                    if g != (w & 0xFFFFFFFF):
                        bad += 1
                        print(f"diff {base + 4 * (i + j):X}: board {g if g is None else f'{g:08X}'} want {w & 0xFFFFFFFF:08X}")
            print(f"r5mon: {len(words)} words compared, {bad} different")
    return 0


if __name__ == "__main__":
    sys.exit(main())
