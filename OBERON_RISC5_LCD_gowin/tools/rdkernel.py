#!/usr/bin/env python3
# rdkernel.py - OBERON_RISC5_FAST O9r: patch Wirth's Kernel.Mod (CR line ends) for a RAM disk in the PSRAM
# instead of the SD card: FS sector s (s = adr DIV 29) is the 1 KB at RDorg + s * 400H, i.e. the .dsk image's
# byte (s - 1) * 1024 at 100000H (loaded by tools/rdload.py); sectors >= RDsecs (3 MB, up to 3FFFFFH) are marked
# used so AllocSector never gives them. Oberon itself stays below 100000H (MemLim 0E7EF0H, display 0E7F00H).
#   rdkernel.py Kernel.Mod [Oberon.Mod]     (patches in place; Oberon.Mod: Load errors to the serial line)
import sys

p = sys.argv[1]
t = open(p, "rb").read().decode("latin-1")
R = "\r"


def sub(old, new):
    global t
    old, new = old.replace("\n", R), new.replace("\n", R)
    assert t.count(old) == 1, old
    t = t.replace(old, new)


sub("    mapsize = 10000H; (*1K sectors, 64MB*)\n",
    "    mapsize = 10000H; (*1K sectors, 64MB*)\n"
    "    RDorg = 0FFC00H; RDsecs = 3072; (*O9r: RAM disk 100000H-3FFFFFH, sector s at RDorg + s*400H*)\n")
sub("    FOR i := 2 TO mapsize DIV 32 - 1 DO sectorMap[i] := {} END\n",
    "    FOR i := 2 TO mapsize DIV 32 - 1 DO sectorMap[i] := {} END ;\n"
    "    FOR i := RDsecs DIV 32 TO mapsize DIV 32 - 1 DO sectorMap[i] := {0 .. 31} END (*O9r*)\n")
sub("""  BEGIN src := src DIV 29; ASSERT(SYSTEM.H(0) = 0);
    src := src * 2 + FSoffset;
    ReadSD(src, SYSTEM.ADR(dst)); ReadSD(src+1, SYSTEM.ADR(dst)+512) 
""", """  BEGIN src := src DIV 29; ASSERT(SYSTEM.H(0) = 0); ASSERT((src > 0) & (src < RDsecs));
    SYSTEM.COPY(RDorg + src*400H, SYSTEM.ADR(dst), 256) (*O9r*)
""")
sub("""  BEGIN dst := dst DIV 29; ASSERT(SYSTEM.H(0) =  0);
    dst := dst * 2 + FSoffset;
    WriteSD(dst, SYSTEM.ADR(src)); WriteSD(dst+1, SYSTEM.ADR(src)+512)
""", """  BEGIN dst := dst DIV 29; ASSERT(SYSTEM.H(0) =  0); ASSERT((dst > 0) & (dst < RDsecs));
    SYSTEM.COPY(SYSTEM.ADR(src), RDorg + dst*400H, 256) (*O9r*)
""")
# the temporary trap (before System's) and Oberon's load errors also go to the serial line (no screen here)
sub("""  PROCEDURE Trap(VAR a: INTEGER; b: INTEGER);
""", """  PROCEDURE Out*(ch: CHAR); (*O9r: a character to the serial line (RS232 data -56, status -52 bit 1)*)
  BEGIN REPEAT UNTIL SYSTEM.BIT(-52, 1); SYSTEM.PUT(-56, ORD(ch))
  END Out;

  PROCEDURE OutHex*(x: INTEGER);
    VAR i, d: INTEGER;
  BEGIN i := 8; REPEAT x := ROR(x, 28); d := x MOD 10H;
      IF d < 10 THEN Out(CHR(d + 30H)) ELSE Out(CHR(d + 37H)) END ; DEC(i)
    UNTIL i = 0
  END OutHex;

  PROCEDURE Trap(VAR a: INTEGER; b: INTEGER);
""")
sub("""    ELSE (*stop*) LED(w + 192); REPEAT UNTIL FALSE
""", """    ELSE (*stop*) Out("T"); Out("R"); Out("A"); Out("P"); Out(" "); OutHex(w); Out(" "); OutHex(u);
      Out(0DX); Out(0AX); LED(w + 192); REPEAT UNTIL FALSE
""")
open(p, "wb").write(t.encode("latin-1"))
print("rdkernel: " + p + " patched for the RAM disk")
if len(sys.argv) > 2:                                # Oberon.Mod: report a failed Load on the serial line
    q = sys.argv[2]
    t = open(q, "rb").read().decode("latin-1")
    sub('Modules.Load("System", Mod); Modules.Load("TTY", Mod);',
        'Modules.Load("System", Mod); LoadErr; Modules.Load("TTY", Mod); LoadErr;')
    sub("""  PROCEDURE Loop*;
""", """  PROCEDURE LoadErr; (*O9r*)
    VAR i: INTEGER;
  BEGIN
    IF Modules.res # 0 THEN i := 0;
      Kernel.Out("l"); Kernel.Out("o"); Kernel.Out("a"); Kernel.Out("d"); Kernel.Out(" "); Kernel.OutHex(Modules.res);
      Kernel.Out(" "); WHILE Modules.importing[i] # 0X DO Kernel.Out(Modules.importing[i]); INC(i) END ;
      Kernel.Out(0DX); Kernel.Out(0AX)
    END
  END LoadErr;

  PROCEDURE Loop*;
""")
    open(q, "wb").write(t.encode("latin-1"))
    print("rdkernel: " + q + " reports load errors")
