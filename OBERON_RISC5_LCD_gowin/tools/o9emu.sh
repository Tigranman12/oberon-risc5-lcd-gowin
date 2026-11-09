#!/bin/bash
# o9emu.sh - OBERON_RISC5_FAST O7/O9 software check: boot build/oberon/Oberon.dsk (tools/mkdisk.sh) in
# oberon-risc-emu's RISC5 core (tools/emu/headless.c, no SDL), type tb/oberon/o9.txt at TTY.Mod's OR> prompts and
# check the answers. Prints "O9 EMU: n/m PASS|FAIL". Usage: tools/o9emu.sh   (from OBERON_RISC5_FAST)
cd "$(dirname "$0")/.." || exit 1
E=${OBERON_EMU:-$HOME/workspace/ext/oberon-risc-emu}/src
# O9r: tools/o9emu.sh rd = build/oberon/OberonRD.dsk (RAM-disk Kernel): 4 MB RAM, the image also at 100000H
sed 's/^#define DefaultMemSize .*/#define DefaultMemSize 0x00400000/' "$E"/risc.c > build/risc4m.c
# trace hook (headless TRACE=file): from the first PC 0 on, the step count and each PC (O9r board/emulator compare)
python3 -I tools/emu/tracehook.py build/risc4m.c
# L2: headless LCD=1 sets MemLim / stackOrg in the boot ROM back to the board's values (struct RISC is private to risc.c)
cat >> build/risc4m.c <<'EOC'
void headless_patch_rom(struct RISC *risc, uint32_t mem_lim, uint32_t stack_org) {   /* o9emu.sh, L2 */
  risc->ROM[372] = 0x61000000 + (mem_lim >> 16);
  risc->ROM[373] = 0x41160000 + (mem_lim & 0x0000FFFF);
  risc->ROM[376] = 0x61000000 + (stack_org >> 16);
}
EOC
cc -O2 -std=c99 -Wall -I"$E" -o build/headless tools/emu/headless.c build/risc4m.c "$E"/risc-fp.c "$E"/disk.c \
    2> build/headless_cc.log || { cat build/headless_cc.log; exit 1; }
D=Oberon; [ "$1" = rd ] && D=OberonRD
cp build/oberon/$D.dsk build/oberon/emu.dsk               # the emulator writes to its disk
[ "$1" = rd ] && export RDISK=build/oberon/emu.dsk
S=build/oberon/emu_screen.pbm
[ "$1" = lcd ] && { export LCD=1; S=build/oberon/emu_lcd.pbm; }   # L2: tools/o9emu.sh lcd = the board's 480 x 272 screen
./build/headless build/oberon/emu.dsk tb/oberon/o9.txt 60000 $S > build/oberon/o9emu.txt
O=build/oberon/o9emu.txt
pass=0; total=0
chk() { total=$((total+1)); if grep -qF -- "$1" $O; then pass=$((pass+1)); echo "PASS: $2"; else echo "FAIL: $2"; fi; }
chk "Oberon V5  NW 14.4.2013" "Oberon boots, System.Log"
chk "Oberon TTY (OBERON_RISC5_FAST)" "TTY loaded after System"
chk "TTY.Mod" "System.Directory *.Mod lists TTY.Mod"
chk "compiling Hello" "ORP.Compile Hello.Mod/s"
chk "1+..+100 = 5050" "Hello.Run"
chk "call error 1 (Nope.Run)" "unknown module: call error"
chk "TRAP   1 in Hello" "Hello.Trap: trap message"
total=$((total+1))
if [ "$(grep -c '1+..+100 = 5050' $O)" -ge 2 ]; then pass=$((pass+1)); echo "PASS: OR> again after the trap"; else echo "FAIL: OR> again after the trap"; fi
chk "Hello	 " "System.ShowModules lists Hello"
[ $pass -eq $total ] && r=PASS || r=FAIL
echo "O9 EMU: $pass/$total $r"
