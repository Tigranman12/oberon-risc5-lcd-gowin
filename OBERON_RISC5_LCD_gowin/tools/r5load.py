#!/usr/bin/env python3
"""r5load.py - OBERON_RISC5_FAST O2: load a program into the board's RAM over the serial line and run it.

  r5load.py prog.s [--adr 4000] [--no-run] [--port /dev/ttyUSB1]   assemble, load with the monitor's l, run with g
  r5load.py prog.s --frame-out f.hex [--sum-out s.hex]               only write the bytes (for tb/tb_mon.v)

The frame is Wirth's LoadFromLine format (BootLoad.Mod): len, adr, len/4 words, then len = 0; every number
4 bytes, lowest first. The monitor answers with the sum of the loaded words (8 hex digits), which must equal
the sum here. Then 'g adr' calls the program; its text is printed until the monitor's 'ok' and prompt.
PuTTY must be closed (one program at a time on the port). The board runs the O2 monitor (help shows '|l').
"""
import argparse
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "r5"))
import r5asm  # noqa: E402


def frame(words, adr):
    b = struct.pack("<II", 4 * len(words), adr)
    b += b"".join(struct.pack("<I", w & 0xFFFFFFFF) for w in words)
    return b + struct.pack("<I", 0)


def checksum(words):
    return sum(words) & 0xFFFFFFFF


def read_until(s, end, timeout):
    buf, t0 = b"", time.time()
    while time.time() - t0 < timeout:
        x = s.read(4096)
        if x:
            buf += x
            if buf.endswith(end):
                return buf.decode("latin-1")
    return None


def main():
    ap = argparse.ArgumentParser(description="load a RISC5 program over the serial line (monitor command l)")
    ap.add_argument("src")
    ap.add_argument("--adr", default="4000", help="load address, hex (default 4000)")
    ap.add_argument("--no-run", action="store_true")
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--timeout", type=float, default=10)
    ap.add_argument("--frame-out")
    ap.add_argument("--sum-out")
    a = ap.parse_args()
    adr = int(a.adr, 16)
    try:
        words, _, _ = r5asm.assemble(open(a.src).read())
    except r5asm.AsmError as e:
        sys.exit(f"r5load: {a.src}: {e}")
    low = 0x1200 <= adr and adr + 4 * len(words) <= 0x7000                    # O6: all of it is the PSRAM
    high = 0x8000 <= adr and adr + 4 * len(words) <= 0x400000
    if adr % 4 or not (low or high):
        sys.exit("r5load: the program must be word aligned in 1200H..6FFFH or 8000H..3FFFFFH (1000H-11FFH: the "
                 "monitor's buffers, 7000H-7EFFH: its stack)")
    fr, want = frame(words, adr), checksum(words)
    if a.frame_out:
        open(a.frame_out, "w").write("".join(f"{x:02X}\n" for x in fr))
        if a.sum_out:
            open(a.sum_out, "w").write(f"{want:08X}\n")
        print(f"r5load: {a.src}: {len(words)} words at {adr:X}H, frame {len(fr)} bytes -> {a.frame_out}, sum {want:08X}")
        return 0
    import serial
    with serial.Serial(a.port, 115200, timeout=0.05) as s:
        s.reset_input_buffer()
        q = time.time()
        while time.time() - q < 0.2:          # old bytes
            if s.read(4096):
                q = time.time()
        s.write(b"\r")                        # a fresh prompt
        if read_until(s, b"r5> ", 2) is None:
            sys.exit("r5load: no 'r5> ' prompt from the board (O2 bitstream? PuTTY still open? press S1)")
        for c in b"l\r":                      # typed like a person: the monitor echoes
            s.write(bytes([c]))
            time.sleep(0.01)
        if read_until(s, b"l\r\n", 2) is None:
            sys.exit("r5load: the monitor did not take 'l'")
        time.sleep(0.02)
        t0 = time.time()
        s.write(fr)
        s.flush()
        ans = read_until(s, b"r5> ", a.timeout)
        if ans is None:
            sys.exit("r5load: no answer after the load (the monitor may still wait for bytes: press S1)")
        got = ans.split("\r\n")[0].strip()
        print(f"r5load: {len(words)} words at {adr:X}H in {time.time() - t0:.2f} s; board sum {got}, "
              f"PC sum {want:08X}: {'OK' if got == f'{want:08X}' else 'DIFFERENT'}")
        if got != f"{want:08X}":
            return 1
        if a.no_run:
            return 0
        for c in f"g {adr:X}\r".encode():
            s.write(bytes([c]))
            time.sleep(0.01)
        out = read_until(s, b"ok\r\nr5> ", a.timeout)
        if out is None:
            sys.exit("r5load: the program did not return 'ok' in time")
        body = out.split("\r\n", 1)[1].rsplit("ok\r\n", 1)[0]
        sys.stdout.write(body.replace("\r\n", "\n"))
        print("r5load: the program returned (ok)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
