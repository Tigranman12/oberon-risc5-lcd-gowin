#!/bin/bash
# o9rsim.sh - OBERON_RISC5_FAST O9r: boot Oberon (build/oberon/OberonRD.dsk) in the RTL simulation: the .dsk is put
# into the PSRAM model at 100000H, the monitor's r starts it, and the PC of each instruction from the inner core's
# start on goes to build/o9r_trace.txt; then the same in the emulator (build/o9r_emu.txt) and the first difference.
#   tools/o9rsim.sh [STEPS]   (default 3000000; run ./run_rf.sh before, for build/tb_mon.vvp)
cd "$(dirname "$0")/.." || exit 1
N=${1:-3000000}
python3 -I - <<'PY'
d = open("build/oberon/OberonRD.dsk", "rb").read()
with open("build/rd_img.hex", "w") as f:
    for k in range(0, len(d), 2):
        f.write("%02X%02X\n" % (d[k + 1], d[k]))
PY
(cd build && vvp -n tb_mon.vvp +o9rsim +steps=$N +tmo=100000 > o9rsim.txt 2>&1)
grep -E 'TTY\||o9rsim|TIMEOUT' build/o9rsim.txt | head -20
cp build/oberon/OberonRD.dsk build/oberon/emu.dsk
TRACE=build/o9r_emu_full.txt RDISK=build/oberon/emu.dsk timeout 300 ./build/headless build/oberon/emu.dsk /dev/null 400 > /dev/null 2>&1
head -n "$N" build/o9r_emu_full.txt > build/o9r_emu.txt; rm -f build/o9r_emu_full.txt
python3 -I - <<'PY'
import itertools
a = open("build/o9r_trace.txt"); b = open("build/o9r_emu.txt")
for k, (x, y) in enumerate(itertools.zip_longest(a, b)):
    if x is None or y is None or int(x, 16) != int(y, 16):
        print("o9rsim: first difference at instruction %d: RTL %s, emulator %s" % (k, (x or "-").strip(), (y or "-").strip()))
        break
else:
    print("o9rsim: RTL and emulator traces equal")
PY
