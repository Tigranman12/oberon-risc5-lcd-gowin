; monitor.s - a small command line in the boot ROM of Wirth's RISC5 (OBERON_RISC5_FAST; copied from
; OBERON_RISC5 stage S2b and given the speed test 'b' in stage F0, PLAN.md).
; Tests from the TTY what hello.s does not use: memory at any address, Wirth's millisecond timer, and the
; multiplier, divider and floating-point units. PuTTY 115200 8N1. Commands (numbers: a, v in hex; m, v, f
; arguments in decimal, '-' allowed):
;   d a        dump 4 words from address a (word aligned; FFFFFFC0 = the I/O registers)
;   w a v      write word v to address a, read it back
;   t          milliseconds since reset (I/O register 0)
;   m a b      a * b: low word in decimal, high word (H) in hex           -> MUL, GETH
;   v a b      a DIV b and a MOD b (b > 0), Oberon's rounding down       -> DIV, GETH
;   f a b      floating point: FLOOR(a+b) FLOOR(a*b) FLOOR(a/b*1000)     -> FLT, FAD, FML, FDV, FLR
;   b n        speed test: n rounds of a loop (load, add, xor, rotate, store, count, branch: 9 clocks
;              each with Wirth's memory, 10 with the F1 memory); prints a checksum (hex) and the time in ms.
;              b 100 -> 807ECFC1, b 1000000 -> 7975FD8D (whatever the clock)
;   g a        call the program at address a (hex) with BL; it returns with B R15 -> 'ok' (F1: ramtest.s)
;   o [fs]     O8: boot Oberon from the SD card (Wirth's BootLoad.LoadFromDisk): fs = the file system's offset in
;              512-byte blocks (hex, default 80000H as Wirth's Kernel); the inner core from block fs+4 on to address 0
;              (the word at 16 = its end), MemLim 0E7EF0H at 12, stackOrg 80000H at 24, SP 80000H, MT (R12) 20H, B 0.
;              OBERON_RISC5_LCD_gowin L2: before B 0 also 53697A67H, 480, 272, 400000H at 0E7F00H-0E7F0CH: Display.Mod
;              (De Wachter's) takes Width, Height and Base from there: Oberon's screen is the 480 x 272 LCD.
;              Block fs+4 is checked first (word 0 = a branch E7xxxxxx, 200H < end <= 20000H), else 'no boot image'
;              and back to r5> (only 0-1FFH written). It only READS the card.
;   r          O9r: boot Oberon from the RAM disk in the PSRAM (tools/rdload.py put the .dsk at 100000H, the
;              RAM-disk Kernel of tools/rdkernel.py): the inner core from 100400H (FS sector 2) to 0, checked and
;              started as o does.
;   s blk n    O7: WRITE n blocks (hex) from block blk on to the SD card, sent over the serial line: '>' first,
;              then per block 512 bytes (binary) -> CMD24, wait until written, read back (CMD17) and compare ->
;              '.' (the next one may come) or '!' (different) / 'sd err', and back to r5>; after the last 'ok'.
;              Buffer 0E0000H-0E03FFH, LEDs = the block number. tools/sdwrite.py sends a disk image.
;   l          O2: load over the serial line in Wirth's LoadFromLine format (BootLoad.Mod): blocks of
;              len, adr, then len/4 words, ending with len = 0 (all 4-byte numbers, lowest byte first, binary);
;              prints the sum of the loaded words (hex) for the sender to compare. tools/r5load.py sends it.
;   ?          help
; Registers: R10 = I/O base (-64), R11 = 4B000000H (float conversion), R14 = stack pointer, R15 = link.
; Routines that call others save R15 on the stack. Line buffer at 1000H, digit buffer at 1100H, stack below 7F00H.
; Labels are lower case without '_' (the META II assembler's limits).

        MOV  R10, -64          ; I/O base
        MOV  R1, 1
        STR  R1, R10, 12       ; RS-232 control: 115200
        STR  R1, R10, 4        ; LEDs: 1
        MOV  R14, 0x7F00       ; stack
        MOVH R11, 0x4B00       ; 4B000000H for FLT / FLR
        PUTS '\r\nRISC5 monitor, ? help\r\n'

main:   PUTS 'r5> '
        BL   readline
        MOV  R9, 0x1000        ; parse the line
cmdsp:  LDB  R5, R9, 0
        ADD  R9, R9, 1
        SUB  R3, R5, 32
        BEQ  cmdsp
        SUB  R3, R5, 0
        BEQ  main              ; empty line
        SUB  R3, R5, 'd'
        BEQ  cmdd
        SUB  R3, R5, 'w'
        BEQ  cmdw
        SUB  R3, R5, 't'
        BEQ  cmdt
        SUB  R3, R5, 'm'
        BEQ  cmdm
        SUB  R3, R5, 'v'
        BEQ  cmdv
        SUB  R3, R5, 'f'
        BEQ  cmdf
        SUB  R3, R5, 'b'
        BEQ  cmdb
        SUB  R3, R5, 'g'
        BEQ  cmdg
        SUB  R3, R5, 'l'
        BEQ  cmdl
        SUB  R3, R5, 'o'
        BEQ  cmdo
        SUB  R3, R5, 's'
        BEQ  cmds
        SUB  R3, R5, 'r'
        BEQ  cmdr
        SUB  R3, R5, '?'
        BEQ  help
err:    PUTS '?\r\n'
        B    main
help:   PUTS 'd a|w a v|t|m|v|f a b|b n|g a|l|o [fs]|s b n|r\r\n'
        B    main

cmdd:   BL   gethex
        SUB  R3, R4, 0
        BEQ  err
        AND  R6, R2, -4        ; word address
        MOV  R7, 4
cdl:    MOV  R2, R6
        BL   phex
        MOV  R1, ':'
        BL   putc
        MOV  R1, 32
        BL   putc
        LDR  R2, R6, 0
        BL   phex
        BL   crlf
        ADD  R6, R6, 4
        SUB  R7, R7, 1
        BNE  cdl
        B    main

cmdw:   BL   gethex
        SUB  R3, R4, 0
        BEQ  err
        AND  R6, R2, -4
        BL   gethex
        SUB  R3, R4, 0
        BEQ  err
        STR  R2, R6, 0
        LDR  R2, R6, 0         ; read back
        BL   phex
        BL   crlf
        B    main

cmdt:   LDR  R2, R10, 0        ; Wirth's ms counter
        BL   pdec
        PUTS ' ms\r\n'
        B    main

cmdm:   BL   getdec
        SUB  R3, R4, 0
        BEQ  err
        MOV  R6, R2
        BL   getdec
        SUB  R3, R4, 0
        BEQ  err
        MUL  R2, R6, R2
        GETH R7                ; high word, before pdec's DIV changes H
        BL   pdec
        MOV  R1, 32
        BL   putc
        MOV  R2, R7
        BL   phex
        BL   crlf
        B    main

cmdv:   BL   getdec
        SUB  R3, R4, 0
        BEQ  err
        MOV  R6, R2
        BL   getdec
        SUB  R3, R4, 0
        BEQ  err
        SUB  R3, R2, 0
        BLE  err               ; Oberon's DIV needs b > 0
        DIV  R2, R6, R2
        GETH R7                ; remainder
        BL   pdec
        MOV  R1, 32
        BL   putc
        MOV  R2, R7
        BL   pdec
        BL   crlf
        B    main

cmdf:   BL   getdec
        SUB  R3, R4, 0
        BEQ  err
        MOV  R6, R2
        BL   getdec
        SUB  R3, R4, 0
        BEQ  err
        MOV  R7, R2
        FLT  R6, R6, R11       ; integer -> float
        FLT  R7, R7, R11
        FAD  R2, R6, R7
        FLR  R2, R2, R11       ; FLOOR
        BL   pdec
        MOV  R1, 32
        BL   putc
        FML  R2, R6, R7
        FLR  R2, R2, R11
        BL   pdec
        SUB  R3, R7, 0         ; b = 0.0: no division
        BEQ  cfe
        MOV  R1, 32
        BL   putc
        FDV  R2, R6, R7
        MOV  R3, 1000
        FLT  R3, R3, R11
        FML  R2, R2, R3
        FLR  R2, R2, R11
        BL   pdec
cfe:    BL   crlf
        B    main

cmdb:   BL   getdec
        SUB  R3, R4, 0
        BEQ  err
        SUB  R3, R2, 0
        BLE  err               ; n > 0
        MOV  R6, R2            ; rounds
        MOV  R7, 0             ; checksum
        MOV  R8, 0x2000        ; the word the loop reads and writes
        STR  R7, R8, 0
        LDR  R5, R10, 0        ; start, ms
bloop:  LDR  R1, R8, 0
        ADD  R1, R1, R6
        XOR  R7, R7, R1
        ROR  R7, R7, 3
        STR  R1, R8, 0
        SUB  R6, R6, 1
        BNE  bloop
        LDR  R6, R10, 0
        SUB  R6, R6, R5        ; elapsed ms
        MOV  R2, R7
        BL   phex
        MOV  R1, 32
        BL   putc
        MOV  R2, R6
        BL   pdec
        PUTS ' ms\r\n'
        B    main

cmdg:   BL   gethex
        SUB  R3, R4, 0
        BEQ  err
        BL   R2                ; the program keeps R10, R11, R14
        PUTS 'ok\r\n'
        B    main

; ---- l (O2): Wirth's LoadFromLine; R5 = address, R6 = bytes left, R7 = sum of the words
cmdl:   MOV  R7, 0
clb:    BL   getw              ; len
        MOV  R6, R2
        BEQ  cle               ; len = 0: done (MOV sets Z)
        BL   getw              ; adr
        MOV  R5, R2
clw:    BL   getw
        STR  R2, R5, 0
        ADD  R7, R7, R2
        ADD  R5, R5, 4
        SUB  R6, R6, 4
        BGT  clw
        B    clb
cle:    MOV  R2, R7
        BL   phex
        BL   crlf
        B    main

; ---- o (O8): boot Oberon from the SD card (see the header). R8 = fs, R9 = block, R7 = destination, R6 = end.
; Its stack is at 0E0000H (the inner core may cover the monitor's at 7F00H).
cmdo:   BL   gethex
        MOV  R8, R2
        SUB  R3, R4, 0
        BNE  co1
        MOVH R8, 8             ; 80000H
co1:    MOVH R14, 0xE
        BL   sdinit
        SUB  R3, R1, 0
        BNE  cosd
        ADD  R9, R8, 4         ; the boot area
        MOV  R7, 0
        BL   sdread
        SUB  R3, R1, 0
        BNE  cosd
        MOV  R2, 0
        LDR  R1, R2, 0         ; word 0: a branch?
        ROR  R1, R1, 24
        AND  R1, R1, 255
        SUB  R3, R1, 0xE7
        BNE  conone
        LDR  R6, R2, 16        ; the end of the inner core
        SUB  R3, R6, 0x201
        BLT  conone
        MOVH R3, 2
        SUB  R3, R6, R3
        BGT  conone
        PUTS 'oberon '
        MOV  R2, R6
        BL   phex
        BL   crlf
col:    SUB  R3, R7, R6        ; WHILE dst < end
        BGE  cogo
        ADD  R9, R9, 1
        BL   sdread
        SUB  R3, R1, 0
        BEQ  col
cosd:   PUTS 'sd err\r\n'
        B    cox
conone: PUTS 'no boot image\r\n'
cox:    MOV  R14, 0x7F00
        B    main
; ---- r (O9r): copy the inner core from the RAM disk (100400H) to 0 and start it as o. R7 = source, R5 = dst.
cmdr:   MOVH R7, 0x10
        ADD  R7, R7, 0x400
        LDR  R1, R7, 0         ; word 0: a branch?
        ROR  R1, R1, 24
        AND  R1, R1, 255
        SUB  R3, R1, 0xE7
        BNE  conone
        LDR  R6, R7, 16        ; the end of the inner core
        SUB  R3, R6, 0x201
        BLT  conone
        MOVH R3, 2
        SUB  R3, R6, R3
        BGT  conone
        PUTS 'oberon '
        MOV  R2, R6
        BL   phex
        BL   crlf
        MOV  R5, 0             ; from here on the monitor's stack (7F00H) may be covered
crl:    LDR  R1, R7, 0
        STR  R1, R5, 0
        ADD  R7, R7, 4
        ADD  R5, R5, 4
        SUB  R3, R5, R6
        BLT  crl
cogo:   MOV  R2, 0
        MOVH R1, 0xE
        IOR  R1, R1, 0x7EF0
        STR  R1, R2, 12        ; MemLim
        MOVH R1, 8
        STR  R1, R2, 24        ; stackOrg
        MOVH R3, 0xE           ; L2 (PLAN.md L-D5): Display.Mod's size words at 0E7F00H: magic 53697A67H,
        IOR  R3, R3, 0x7F00    ; Width 480, Height 272, Base 400000H (the LCD frame memory, rtl/r5_lcd.v)
        MOVH R1, 0x5369
        IOR  R1, R1, 0x7A67
        STR  R1, R3, 0
        MOV  R1, 480
        STR  R1, R3, 4
        MOV  R1, 272
        STR  R1, R3, 8
        MOVH R1, 0x40
        STR  R1, R3, 12
        MOV  R1, 0x84
        STR  R1, R10, 4        ; LEDs as Wirth's BootLoad at the end
        MOVH R14, 8            ; SP
        MOV  R12, 0x20         ; MT
        MOV  R15, 0
        B    R2                ; to the inner core

; ---- s (O7): write n blocks from the serial line to the SD card (see the header). R9 = block, R8 = blocks left,
; R7 = pointer, R6 = counter. Wirth's Kernel.WriteSD: CMD24, token FEH, 128 words fast, 2 CRC bytes, data
; response xxx00101, busy (00) until FFH.
cmds:   BL   gethex            ; (R9 is the line pointer until both numbers are read)
        SUB  R3, R4, 0
        BEQ  err
        MOV  R6, R2
        BL   gethex
        SUB  R3, R4, 0
        BEQ  err
        MOV  R8, R2
        BEQ  err               ; n = 0 (MOV sets Z)
        MOV  R9, R6
        BL   sdinit
        SUB  R3, R1, 0
        BNE  cosd
        MOV  R1, '>'
        BL   putc
csb:    MOVH R7, 0xE           ; receive the block to 0E0000H
        MOV  R6, 128
csw:    BL   getw
        STR  R2, R7, 0
        ADD  R7, R7, 4
        SUB  R6, R6, 1
        BNE  csw
        MOV  R4, 24
        MOV  R5, R9
        BL   sdadr
        BL   sdcmd
        SUB  R3, R1, 0
        BNE  cserr
        MOV  R1, 0xFE          ; start token
        BL   spi
        MOV  R1, 5             ; selected, fast
        STR  R1, R10, 20
        MOVH R7, 0xE
        MOV  R6, 128
csd:    LDR  R1, R7, 0
        BL   spi
        ADD  R7, R7, 4
        SUB  R6, R6, 1
        BNE  csd
        MOV  R1, 1             ; selected, slow
        STR  R1, R10, 20
        MOV  R1, 255
        BL   spi
        MOV  R1, 255
        BL   spi               ; CRC (not checked by the card in SPI mode)
        MOV  R6, 100
csr:    MOV  R1, 255           ; data response
        BL   spi
        AND  R1, R1, 31
        SUB  R3, R1, 5
        BEQ  csy
        SUB  R6, R6, 1
        BNE  csr
        B    cserr
csy:    MOVH R6, 0x10          ; busy (00) until FFH, at most 100000H bytes
csyl:   MOV  R1, 255
        BL   spi
        SUB  R3, R1, 255
        BEQ  csv
        SUB  R6, R6, 1
        BNE  csyl
        B    cserr
csv:    MOV  R1, 0
        STR  R1, R10, 20
        MOV  R1, 255
        BL   spi
        MOVH R7, 0xE           ; read it back to 0E0200H
        ADD  R7, R7, 0x200
        BL   sdread
        SUB  R3, R1, 0
        BNE  cosd
        MOVH R7, 0xE
        MOV  R6, 128
csc:    LDR  R1, R7, 0
        LDR  R2, R7, 0x200
        SUB  R3, R1, R2
        BNE  csbad
        ADD  R7, R7, 4
        SUB  R6, R6, 1
        BNE  csc
        STR  R9, R10, 4        ; LEDs
        ADD  R9, R9, 1
        MOV  R1, '.'
        BL   putc
        SUB  R8, R8, 1
        BNE  csb
        BL   crlf
        PUTS 'ok\r\n'
        B    main
csbad:  PUTS '!\r\n'
        B    main
cserr:  MOV  R1, 0
        STR  R1, R10, 20
        B    cosd

; ---- SD card (SPI, Wirth's SPI.v at I/O 4 / 5; from sdtest.s). sdinit: R1 := 0 if the card is ready (CMD0, CMD8,
; ACMD41 with HCS, CMD58 (CCS: SDHC or SDSC), CMD16 512), else 1. Uses R1-R6.
sdinit: SUB  R14, R14, 4
        STR  R15, R14, 0
        MOV  R1, 0
        STR  R1, R10, 20
        MOV  R6, 10
si1:    MOV  R1, 255           ; 80 clocks deselected
        BL   spi
        SUB  R6, R6, 1
        BNE  si1
        MOV  R4, 0
        MOV  R5, 0
        BL   sdcmd
        SUB  R3, R1, 1
        BNE  sie
        MOV  R4, 8
        MOV  R5, 0x1AA
        BL   sdcmd
        BL   sd4
        MOV  R6, 0
si3:    ADD  R6, R6, 1
        MOV  R4, 55
        MOV  R5, 0
        BL   sdcmd
        MOV  R4, 41
        MOVH R5, 0x4000
        BL   sdcmd
        SUB  R3, R1, 0
        BEQ  si4
        SUB  R3, R6, 4000
        BLT  si3
        B    sie
si4:    MOV  R4, 58
        MOV  R5, 0
        BL   sdcmd
        MOV  R1, 255           ; OCR's first byte: bit 6 = CCS (1: SDHC, block addresses; 0: SDSC, byte
        BL   spi               ; addresses, as Wirth's Kernel.SDShift); kept at 0E0400H for sdadr
        AND  R1, R1, 0x40
        MOVH R3, 0xE
        STR  R1, R3, 0x400
        MOV  R5, 3
        BL   sd4l0
        MOV  R4, 16
        MOV  R5, 512
        BL   sdcmd
        MOV  R1, 0
        B    six
sie:    MOV  R1, 1
six:    LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15
; sd4: 4 more bytes (CMD8's answer, not looked at); sd4l0: R5 more bytes. Uses R1, R3, R5.
; sdadr: the card address of block R5 in R5: R5 * 512 on an SDSC card (O7: the 2 GB card in the Tang Nano is
; one; sdinit keeps CCS at 0E0400H). Uses R3.
sdadr:  MOVH R3, 0xE
        LDR  R3, R3, 0x400
        SUB  R3, R3, 0
        BNE  sdax
        LSL  R5, R5, 9
sdax:   B    R15
sd4:    MOV  R5, 4
sd4l0:  SUB  R14, R14, 4
        STR  R15, R14, 0
sd4l:   MOV  R1, 255
        BL   spi
        SUB  R5, R5, 1
        BNE  sd4l
        LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15
; sdread: block R9 to R7.. (R7 += 512), Wirth's ReadSD: CMD17, token FEH, 128 words fast (LSByte first), 2 CRC
; bytes. R1 := 0 if ok, else 1. Uses R1-R5, R13.
sdread: SUB  R14, R14, 4
        STR  R15, R14, 0
        MOV  R4, 17
        MOV  R5, R9
        BL   sdadr
        BL   sdcmd
        SUB  R3, R1, 0
        BNE  sre
        MOVH R13, 1
srt:    MOV  R1, 255
        BL   spi
        SUB  R3, R1, 0xFE
        BEQ  srk
        SUB  R13, R13, 1
        BNE  srt
        B    sre
srk:    MOV  R1, 5             ; selected, fast
        STR  R1, R10, 20
        MOV  R13, 128
srw:    MOV  R1, -1
        BL   spi
        STR  R1, R7, 0
        ADD  R7, R7, 4
        SUB  R13, R13, 1
        BNE  srw
        MOV  R1, 1
        STR  R1, R10, 20
        MOV  R1, 255
        BL   spi
        MOV  R1, 255
        BL   spi
        MOV  R1, 0
        STR  R1, R10, 20
        MOV  R1, 255
        BL   spi
        MOV  R1, 0
        B    srx
sre:    MOV  R1, 0
        STR  R1, R10, 20
        MOV  R1, 1
srx:    LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15
; spi: send R1 (slow: its low byte; fast: the word), R1 := the byte / word received. Uses R3.
spi:    STR  R1, R10, 16
spw:    LDR  R3, R10, 20
        AND  R3, R3, 1
        BEQ  spw
        LDR  R1, R10, 16
        B    R15
; sdcmd: command R4, argument R5 (Wirth's SPICmd), R1 := the R1 answer (< 80H) or FFH; the card stays selected.
; Uses R1, R2, R3.
sdcmd:  SUB  R14, R14, 4
        STR  R15, R14, 0
        MOV  R1, 0
        STR  R1, R10, 20
        MOV  R1, 255
        BL   spi
        MOV  R1, 1
        STR  R1, R10, 20
        MOV  R2, 0
scw:    MOV  R1, 255           ; until the card is not busy
        BL   spi
        SUB  R3, R1, 255
        BEQ  scs
        ADD  R2, R2, 1
        SUB  R3, R2, 10000
        BLT  scw
scs:    IOR  R1, R4, 0x40
        BL   spi
        ROR  R1, R5, 24
        BL   spi
        ROR  R1, R5, 16
        BL   spi
        ROR  R1, R5, 8
        BL   spi
        MOV  R1, R5
        BL   spi
        MOV  R1, 0xFF
        SUB  R3, R4, 0
        BNE  sc8
        MOV  R1, 0x95
sc8:    SUB  R3, R4, 8
        BNE  scc
        MOV  R1, 0x87
scc:    BL   spi
        MOV  R2, 32
scr:    MOV  R1, 255
        BL   spi
        SUB  R3, R1, 0x80
        BLT  scx
        SUB  R2, R2, 1
        BNE  scr
scx:    LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15

; ---- getw (O2): R2 := the next 4 bytes, lowest first (uses R1, R3, R4); getc inline, no stack:
; each byte goes into the low 8 bits, then R2 turns 8 bits right; after 4 bytes the first is at the bottom
getw:   MOV  R2, 0
        MOV  R4, 4
gwl:    LDR  R3, R10, 12
        AND  R3, R3, 1         ; rdyRx
        BEQ  gwl
        LDR  R1, R10, 8
        IOR  R2, R2, R1
        ROR  R2, R2, 8
        SUB  R4, R4, 1
        BNE  gwl
        B    R15

; ---- putc: send R1 (uses R3)
putc:   LDR  R3, R10, 12
        AND  R3, R3, 2         ; rdyTx
        BEQ  putc
        STR  R1, R10, 8
        B    R15

; ---- getc: R1 := next key (uses R3)
getc:   LDR  R3, R10, 12
        AND  R3, R3, 1         ; rdyRx
        BEQ  getc
        LDR  R1, R10, 8
        B    R15

; ---- crlf (uses R1, R3)
crlf:   SUB  R14, R14, 4
        STR  R15, R14, 0
        MOV  R1, 13
        BL   putc
        MOV  R1, 10
        BL   putc
        LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15

; ---- readline: a line into 1000H with echo, Backspace/DEL, 60 characters, 0 at the end
readline: SUB R14, R14, 4
        STR  R15, R14, 0
        MOV  R8, 0x1000
        MOV  R9, 0
rl:     BL   getc
        SUB  R3, R1, 13
        BEQ  rlend
        SUB  R3, R1, 8
        BEQ  rlbs
        SUB  R3, R1, 127
        BEQ  rlbs
        SUB  R3, R1, 32
        BLT  rl                ; other control keys: ignored
        SUB  R3, R9, 60
        BGE  rl                ; line full
        ADD  R3, R8, R9
        STB  R1, R3, 0
        ADD  R9, R9, 1
        BL   putc              ; echo
        B    rl
rlbs:   SUB  R3, R9, 0
        BEQ  rl
        SUB  R9, R9, 1
        MOV  R1, 8             ; back, space, back
        BL   putc
        MOV  R1, 32
        BL   putc
        MOV  R1, 8
        BL   putc
        B    rl
rlend:  ADD  R3, R8, R9
        MOV  R1, 0
        STB  R1, R3, 0
        BL   crlf
        LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15

; ---- gethex: R2 := hex number at R9 (R9 moves on), R4 := number of digits (0 = none); uses R3, R12, R13
gethex: MOV  R2, 0
        MOV  R4, 0
ghsp:   LDB  R3, R9, 0
        SUB  R12, R3, 32
        BNE  ghd
        ADD  R9, R9, 1
        B    ghsp
ghd:    LDB  R3, R9, 0
        SUB  R12, R3, '0'
        BLT  ghx
        SUB  R13, R12, 10
        BLT  ghadd             ; 0..9
        IOR  R3, R3, 32        ; lower case
        SUB  R12, R3, 'a'
        BLT  ghx
        SUB  R13, R12, 6
        BGE  ghx
        ADD  R12, R12, 10      ; a..f
ghadd:  LSL  R2, R2, 4
        IOR  R2, R2, R12
        ADD  R4, R4, 1
        ADD  R9, R9, 1
        B    ghd
ghx:    B    R15

; ---- getdec: R2 := decimal number at R9 ('-' allowed), R4 := digits; uses R3, R5, R12, R13; MUL by 10
getdec: MOV  R2, 0
        MOV  R4, 0
gdsp:   LDB  R3, R9, 0
        SUB  R12, R3, 32
        BNE  gdsg
        ADD  R9, R9, 1
        B    gdsp
gdsg:   MOV  R5, 0
        SUB  R12, R3, '-'
        BNE  gdd
        MOV  R5, 1
        ADD  R9, R9, 1
gdd:    LDB  R3, R9, 0
        SUB  R12, R3, '0'
        BLT  gdx
        SUB  R13, R12, 10
        BGE  gdx
        MUL  R2, R2, 10
        ADD  R2, R2, R12
        ADD  R4, R4, 1
        ADD  R9, R9, 1
        B    gdd
gdx:    SUB  R12, R5, 0
        BEQ  gdr
        MOV  R12, 0
        SUB  R2, R12, R2       ; negative
gdr:    B    R15

; ---- phex: R2 as 8 hex digits (R2 unchanged); uses R1, R3, R13
phex:   SUB  R14, R14, 4
        STR  R15, R14, 0
        MOV  R13, 8
phl:    ROR  R2, R2, 28        ; next 4 bits to the bottom
        AND  R1, R2, 15
        SUB  R3, R1, 10
        BLT  phd
        ADD  R1, R1, 7         ; 'A' - '0' - 10
phd:    ADD  R1, R1, '0'
        BL   putc
        SUB  R13, R13, 1
        BNE  phl
        LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15

; ---- pdec: R2 as a signed decimal; uses R1..R4, R12, R13; DIV and MUL by 10
pdec:   SUB  R14, R14, 4
        STR  R15, R14, 0
        SUB  R3, R2, 0
        BGE  pdp
        MOV  R1, '-'
        BL   putc
        MOV  R3, 0
        SUB  R2, R3, R2
pdp:    MOV  R12, 0x1100       ; digits, last first
        MOV  R13, 0
pdl:    DIV  R3, R2, 10
        MUL  R1, R3, 10
        SUB  R1, R2, R1        ; R2 MOD 10
        ADD  R1, R1, '0'
        ADD  R4, R12, R13
        STB  R1, R4, 0
        ADD  R13, R13, 1
        MOV  R2, R3            ; sets Z when the rest is 0
        BNE  pdl
pdo:    SUB  R13, R13, 1
        ADD  R4, R12, R13
        LDB  R1, R4, 0
        BL   putc
        SUB  R3, R13, 0
        BNE  pdo
        LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15
