#!/bin/bash
# OBERON_RISC5_LCD_gowin L1: the LCD frame memory and controller alone (tb/tb_lcd.v, rtl/r5_lcd.v), a few seconds.
# Last lines: "RESULT: n/m" and "TB PASS" (exit 0) or "TB FAIL". Output: build/tb_lcd.txt, build/lcd_frame.pbm.
# Usage:  ./run_lcd.sh   (fast; the full monitor test with lcdtest.s is run_rf.sh)
cd "$(dirname "$0")" && mkdir -p build
ok=0
for r in 1 0; do                    # ROT180 = 1 (the board's), then 0
    iverilog -g2005 -Wall -s tb_lcd -Ptb_lcd.ROT=$r -o build/tb_lcd.vvp tb/tb_lcd.v rtl/r5_lcd.v || exit 1
    (cd build && vvp -n tb_lcd.vvp > tb_lcd_rot$r.txt)
    echo "ROT180=$r:"; grep -vE '^PASS' build/tb_lcd_rot$r.txt
    grep -q "^TB PASS" build/tb_lcd_rot$r.txt && ok=$((ok+1))
done
cp build/lcd_frame.pbm build/lcd_frame_rot0.pbm
[ $ok = 2 ] && echo "LCD TB: 2/2 PASS" || { echo "LCD TB FAIL"; exit 1; }
