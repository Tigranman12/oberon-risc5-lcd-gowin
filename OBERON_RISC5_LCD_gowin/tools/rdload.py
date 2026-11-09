#!/usr/bin/env python3
# rdload.py - OBERON_RISC5_FAST O9r: put an Oberon .dsk (RAMDISK=1 tools/mkdisk.sh -> build/oberon/OberonRD.dsk)
# into the PSRAM at 100000H with the monitor's l (64 KB per l, each sum compared), then boot it with r and, with
# --script, type each line of the script at Oberon's OR> prompt (TTY.Mod) and print what comes back.
# The RAM disk is lost at power-off (load it again). PuTTY must be closed.
#   rdload.py [IMAGE] [--script tb/oberon/o9.txt] [--no-boot] [--wait 20] [--port /dev/ttyUSB1]
import argparse
import struct
import sys
import time

import serial

BASE, CHUNK = 0x100000, 0x10000
last = b""                                           # what came before a timeout


def read_until(s, end, timeout):
    global last
    buf, t0 = b"", time.time()
    while time.time() - t0 < timeout:
        x = s.read(4096)
        if x:
            buf += x
            if end is not None and buf.endswith(end):
                return buf
    last = buf
    return buf if end is None else None                  # end None: all that came in the time


def typed(s, text):
    for c in text.encode():
        s.write(bytes([c]))
        time.sleep(0.01)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image", nargs="?", default="build/oberon/OberonRD.dsk")
    ap.add_argument("--script")
    ap.add_argument("--no-boot", action="store_true")
    ap.add_argument("--wait", type=float, default=20, help="seconds to wait for each OR> prompt")
    ap.add_argument("--port", default="/dev/ttyUSB1")
    a = ap.parse_args()
    data = open(a.image, "rb").read()
    data += bytes(-len(data) % 4)
    if len(data) > 0x300000:
        sys.exit("rdload: the image is bigger than the RAM disk (3 MB)")
    with serial.Serial(a.port, 115200, timeout=0.05) as s:
        q = time.time()
        while time.time() - q < 0.2:
            if s.read(4096):
                q = time.time()
        s.write(b"\r")
        if read_until(s, b"r5> ", 2) is None:
            sys.exit("rdload: no r5> prompt (PuTTY open? press S1)")
        t0 = time.time()
        for off in range(0, len(data), CHUNK):
            part = data[off:off + CHUNK]
            words = struct.unpack(f"<{len(part) // 4}I", part)
            want = f"{sum(words) & 0xFFFFFFFF:08X}"
            typed(s, "l\r")
            if read_until(s, b"l\r\n", 2) is None:
                sys.exit("rdload: the monitor did not take l")
            time.sleep(0.02)
            s.write(struct.pack("<II", len(part), BASE + off) + part + struct.pack("<I", 0))
            ans = read_until(s, b"r5> ", 30)
            got = ans.decode("latin-1").split("\r\n")[0].strip() if ans else None
            if got != want:
                sys.exit(f"rdload: at {BASE + off:X}H board sum {got}, PC sum {want} (press S1, try again)")
            print(f"rdload: {off + len(part):7d}/{len(data)} bytes, {time.time() - t0:.0f} s", flush=True)
        print(f"rdload: {a.image} at {BASE:X}H..{BASE + len(data) - 1:X}H, all sums equal")
        if a.no_boot:
            return 0
        typed(s, "r\r")
        out = read_until(s, b"OR> ", a.wait)
        if out is None:
            sys.exit(f"rdload: no OR> after r: {last!r}")
        sys.stdout.write(out.decode("latin-1").replace("\r\n", "\n").replace("\r", "\n"))
        if a.script:
            for line in open(a.script).read().splitlines():
                typed(s, line + "\r")
                out = read_until(s, b"OR> ", a.wait)
                if out is None:
                    sys.exit(f"\nrdload: no OR> after {line!r}: {last!r}")
                sys.stdout.write(out.decode("latin-1").replace("\r\n", "\n").replace("\r", "\n"))
            print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
