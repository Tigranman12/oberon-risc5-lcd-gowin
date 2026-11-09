#!/usr/bin/env python3
# mkcore.py - OBERON_RISC5_FAST O8: build the SD model's boot image from programs/coretest.s (a stand-in for
# Oberon's inner core): the code at address 0, the word at address 16 = the size in bytes (as Wirth's linker puts the end of the
# inner core there), words from the code's end to the size = a table (so 'o' must read several blocks).
# Writes build/core_img.hex (bytes, $readmemh, lowest byte of each word first = the card's order),
# build/core_end.hex and build/core_sum.hex (sum of the words 100H..end, what coretest prints).
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "r5"))
import r5asm  # noqa: E402

SIZE = 0x6A8            # 1704 bytes: 3 full blocks + part of a 4th
words, _, _ = r5asm.assemble(open(os.path.join(HERE, "..", "programs", "coretest.s")).read())
assert (words[0] >> 24) & 0xFF == 0xE7, "word 0 must be a branch"
assert len(words) * 4 <= 0x100 + 0x200, "coretest.s too long"
words = [w & 0xFFFFFFFF for w in words] + [0] * (SIZE // 4 - len(words))
for i in range(0x100 // 4, SIZE // 4):
    if i >= 0x100 // 4 and words[i] == 0 and i * 4 >= 0x100 + 0x200:
        words[i] = (i * 0x9E3779B1 + 0x1234567) & 0xFFFFFFFF
words[4] = SIZE                 # address 16 (Wirth: SYSTEM.GET(16, lim); CoreLinker buffer[4])
s = sum(words[0x100 // 4:]) & 0xFFFFFFFF
out = os.path.join(HERE, "..", "build")
with open(os.path.join(out, "core_img.hex"), "w") as f:
    for w in words:
        for k in range(4):
            f.write("%02X\n" % ((w >> (8 * k)) & 0xFF))
open(os.path.join(out, "core_end.hex"), "w").write("%08X\n" % SIZE)
# O9r: the same core as an l frame to the RAM disk's FS sector 2 (100400H) for the monitor's r (+o9r in tb_mon)
fr = [SIZE, 0x100400] + words + [0]
with open(os.path.join(out, "load_rdcore.hex"), "w") as f:
    for w in fr:
        for k in range(4):
            f.write("%02X\n" % ((w >> (8 * k)) & 0xFF))
open(os.path.join(out, "load_rdcore_sum.hex"), "w").write("%08X\n" % (sum(words) & 0xFFFFFFFF))
open(os.path.join(out, "core_sum.hex"), "w").write("%08X\n" % s)
print("mkcore: %d words, end %XH, sum %08X -> build/core_img.hex" % (len(words), SIZE, s))
