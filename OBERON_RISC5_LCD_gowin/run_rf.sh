#!/bin/bash
# OBERON_RISC5_LCD_gowin (from OBERON_RISC5_FAST; L1: + the LCD frame memory, lcdtest.s): assemble programs/monitor.s into the boot ROM (build/prom.mem), then simulate r5_tang
# (RISC5F + UART; O6: memory = the PSRAM model through the cache) with the terminal model tb/tb_mon.v; programs/ramtest.s is preloaded in the PSRAM model. Last lines: "RESULT: n/m" and "TB PASS"
# (exit 0) or "TB FAIL". The assembler is ../tools/r5/r5asm.py; Wirth's unchanged Verilog is used from ../OBERON_RISC5 (read only).
# The Gowin build (gowin/build.tcl) puts the LAST assembled build/prom.mem into the bitstream.
# Usage:  runlog rf_sim ./run_rf.sh        Output: build/prom.mem (+ .lst), build/tb_mon.txt
cd "$(dirname "$0")" || exit 1
mkdir -p build
R=../OBERON_RISC5
python3 ../tools/r5/r5asm.py programs/monitor.s -o build/prom.mem --words 1024 || exit 1   # O8: 1024-word ROM
python3 tools/mkcore.py || exit 1   # O8: the SD model's test inner core
python3 ../tools/r5/r5asm.py programs/ramtest.s -o build/ramtest.mem --words 64 || exit 1
python3 tools/r5load.py programs/primes.s --frame-out build/load_primes.hex --sum-out build/load_primes_sum.hex || exit 1   # O2
sed 's/^\.equ NWH, .*/.equ NWH, 0/; s/^\.equ NWL, .*/.equ NWL, 256/' programs/psramtest.s > build/psramtest_sim.s   # O3: 256 words
python3 tools/r5load.py build/psramtest_sim.s --frame-out build/load_psram.hex --sum-out build/load_psram_sum.hex || exit 1
python3 tools/r5load.py programs/sdtest.s --frame-out build/load_sd.hex --sum-out build/load_sd_sum.hex || exit 1   # O4
python3 tools/r5load.py programs/lcdtest.s --frame-out build/load_lcd.hex --sum-out build/load_lcd_sum.hex || exit 1   # L1
# O5: primes.s twice on the same cache lines (index 0-9); O6: at 10000H (p1) and 18000H (p2), 32 KB apart
python3 tools/r5load.py programs/primes.s --adr 10000 --frame-out build/load_primes_p1.hex --sum-out build/load_primes_p1_sum.hex || exit 1
python3 tools/r5load.py programs/primes.s --adr 18000 --frame-out build/load_primes_p2.hex --sum-out build/load_primes_p2_sum.hex || exit 1
W=$R/rtl/wirth
GP=/tools/Gowin/IDE/simlib/gw1n/prim_sim.v   # O6: the cache's SDPB primitives
iverilog -g2005 -s tb_mon -o build/tb_mon.vvp tb/tb_mon.v rtl/r5_tang.v rtl/RISC5F.v rtl/r5_prom.v rtl/r5_psram.v rtl/r5_cache.v rtl/r5_lcd.v tb/hyperram_model.v tb/sd_spi_model.v $R/rtl/port/*.v $GP \
    $W/Multiplier.v $W/Divider.v $W/FPAdder.v $W/FPMultiplier.v $W/FPDivider.v $W/SPI.v || exit 1
cd build && vvp -n tb_mon.vvp +sdimg +sdwrite "$@" | tee tb_mon.txt   # ./run_rf.sh +o5: only the O3 / O5 parts
grep -q "^TB PASS" tb_mon.txt || exit 1
# O3: the PSRAM controller alone against the HyperRAM model, 6 latency / delay settings
cd .. && ok=0
for v in "6 1 3.0" "6 1 1.0" "6 1 7.0" "3 1 3.0" "7 1 3.0" "4 0 3.0"; do
    set -- $v
    iverilog -g2005 -s tb_psram -Ptb_psram.LC=$1 -Ptb_psram.FIXED=$2 -Ptb_psram.TCKD=$3 -o build/tb_psram.vvp \
        tb/tb_psram.v rtl/r5_psram.v tb/hyperram_model.v || exit 1
    vvp -n build/tb_psram.vvp | grep "PSRAM TB" | tee -a build/tb_mon.txt | grep -q PASS && ok=$((ok+1))
done
[ $ok -eq 6 ] && echo "O3 PSRAM TB: 6/6 PASS" || { echo "O3 PSRAM TB FAIL"; exit 1; }
