#!/bin/bash
# mkdisk.sh - OBERON_RISC5_FAST O7/O9: build the Oberon disk image build/oberon/Oberon.dsk with Peter De Wachter's
# project-norebo (~/workspace/ext/project-norebo, `make` run there, sources fetched into upstream/; the fonts and
# TTL libraries of the vanished paddedcell.com zips extracted from oberon-risc-emu's Oberon-2020-08-18.dsk with
# tools/odsk.py). Changes to Wirth's system: oberon/*.Mod added (TTY.Mod compiled, Hello.Mod only installed),
# Oberon.Mod loads TTY after System. Usage: tools/mkdisk.sh   (from OBERON_RISC5_FAST)
# RAMDISK=1 tools/mkdisk.sh (O9r): Kernel.Mod patched by tools/rdkernel.py (the disk in the PSRAM at 100000H)
# -> build/oberon/OberonRD.dsk instead.
set -e
NB=${NOREBO:-$HOME/workspace/ext/project-norebo}
HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$HERE/build/norebo
rm -rf "$W"; mkdir -p "$W"
cp -r "$NB"/norebo "$NB"/build-image.py "$NB"/manifest.csv "$NB"/Norebo "$NB"/Oberon "$NB"/Bootstrap "$W"/
cp -r "$NB"/upstream "$W"/src
for f in "$HERE"/oberon/*.Mod; do tr -d '\r' < "$f" | tr '\n' '\r' > "$W/src/$(basename "$f")"; done
# Oberon.Mod: load TTY (O9) after System
grep -q 'Modules.Load("System", Mod); Mod := NIL; Loop' "$W"/src/Oberon.Mod
sed -i 's/Modules.Load("System", Mod); Mod := NIL; Loop/Modules.Load("System", Mod); Modules.Load("TTY", Mod); Mod := NIL; Loop/' "$W"/src/Oberon.Mod
grep -q 'Modules.Load("TTY", Mod)' "$W"/src/Oberon.Mod
sed -i "/^source,Clipboard.Mod,/d" "$W"/manifest.csv        # emulator only (and not fetched)
echo "source,TTY.Mod,local" >> "$W"/manifest.csv
OUT=Oberon
if [ -n "$RAMDISK" ]; then python3 -I "$HERE"/tools/rdkernel.py "$W"/src/Kernel.Mod "$W"/src/Oberon.Mod; OUT=OberonRD; fi
(cd "$W" && ./build-image.py src) > "$HERE"/build/mkdisk.log 2>&1 || { tail -20 "$HERE"/build/mkdisk.log; exit 1; }
mkdir -p "$HERE"/build/oberon
cp "$W"/build/Oberon.dsk "$HERE"/build/oberon/$OUT.dsk
python3 -I "$HERE"/tools/odsk.py "$HERE"/build/oberon/$OUT.dsk > "$HERE"/build/oberon/files.txt
echo "mkdisk: build/oberon/$OUT.dsk $(stat -c %s "$HERE"/build/oberon/$OUT.dsk) bytes, $(wc -l < "$HERE"/build/oberon/files.txt) files"
