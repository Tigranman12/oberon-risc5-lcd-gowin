#!/usr/bin/env python3
# sdwrite.py - OBERON_RISC5_FAST O7: write a disk image to the SD card in the Tang Nano through the monitor's
# 's blk n' command (programs/monitor.s): '>' first, then per 512-byte block one '.' after the board has written
# it and read it back equal. ERASES what is on the card at those blocks. PuTTY must be closed.
#   sdwrite.py IMAGE [--block 80002] [--skip K] [--count N] [--port /dev/ttyUSB1]
#   IMAGE's block k goes to card block blk + k (an Oberon .dsk starts with FS sector 1 = block FSoffset + 2);
#   --skip K starts at image block K (to go on after an error); --count N writes N blocks only.
import argparse
import sys
import time

import serial


last = b""                                           # what came before a timeout (for the error text)


def read_until(s, end, timeout, buf=b"", anywhere=False):
    global last
    t0 = time.time()
    while time.time() - t0 < timeout:
        if (end in buf) if anywhere else buf.endswith(end):
            return buf
        x = s.read(4096)
        if x:
            buf += x
    last = buf
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--block", default="80002")
    ap.add_argument("--skip", type=int, default=0)
    ap.add_argument("--count", type=int, default=0)
    ap.add_argument("--port", default="/dev/ttyUSB1")
    a = ap.parse_args()
    data = open(a.image, "rb").read()
    data += bytes(-len(data) % 512)
    nblk = len(data) // 512
    first = a.skip
    n = (a.count or nblk - first)
    n = min(n, nblk - first)
    if n <= 0:
        sys.exit("sdwrite: nothing to write")
    blk = int(a.block, 16) + first
    with serial.Serial(a.port, 115200, timeout=0.05) as s:
        q = time.time()
        while time.time() - q < 0.2:                 # stale bytes from before
            if s.read(4096):
                q = time.time()
        s.write(b"\r")
        if read_until(s, b"r5> ", 2) is None:
            sys.exit("sdwrite: no r5> prompt")
        for c in f"s {blk:X} {n:X}\r".encode():
            s.write(bytes([c]))
            time.sleep(0.005)
        r = read_until(s, b"\n>", 10)                 # not the '>' of a prompt 'r5> ' (an error)
        if r is None:
            sys.exit(f"sdwrite: no '>' (sd err?): {last!r}")
        t0, rest = time.time(), b""
        for k in range(n):
            i = first + k
            s.write(data[512 * i:512 * i + 512])
            r = read_until(s, b".", 5, rest, anywhere=True)  # after the last block '.', 'ok' and 'r5> ' can
            if r is None:                                     # come in one read
                got = last
                got += read_until(s, b"r5> ", 3) or last
                sys.exit(f"sdwrite: block {blk + k:X} (image block {i}) failed ('!' = read back different): "
                         f"{got!r}; "
                         f"go on with --skip {i}")
            rest = r[r.index(b".") + 1:]
            if k % 100 == 99 or k == n - 1:
                el = time.time() - t0
                print(f"sdwrite: {k + 1}/{n} blocks, {el:.0f} s", flush=True)
        r = read_until(s, b"r5> ", 5, rest) or rest
        print(r.decode("latin-1").strip())
        if b"ok" not in r:
            sys.exit("sdwrite: no ok at the end")
    print(f"sdwrite: blocks {blk:X}..{blk + n - 1:X} written and read back")
    return 0


if __name__ == "__main__":
    sys.exit(main())
