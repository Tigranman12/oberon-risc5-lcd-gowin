#!/usr/bin/env python3
# mksdw.py - OBERON_RISC5_FAST O7: build/sdwtest.s = programs/sdwtest.s + the monitor's SD and print routines
# (sdinit .. sdcmd, putc, crlf, phex from programs/monitor.s). Then: tools/r5load.py build/sdwtest.s --adr 4000
import os

here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
m = open(os.path.join(here, "programs/monitor.s")).read().split("\n")


def rng(a, b):
    i = next(k for k, ln in enumerate(m) if ln.startswith(a))
    j = next(k for k, ln in enumerate(m) if k > i and ln.startswith(b))
    return m[i:j]


out = open(os.path.join(here, "programs/sdwtest.s")).read().split("\n")
for a, b in [("sdinit:", "; ---- getw"), ("putc:", "; ---- getc"), ("crlf:", "; ---- readline"), ("phex:", "; ---- pdec")]:
    out += rng(a, b)
open(os.path.join(here, "build/sdwtest.s"), "w").write("\n".join(out) + "\n")
print("mksdw: build/sdwtest.s")
