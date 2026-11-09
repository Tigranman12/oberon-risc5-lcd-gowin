; sdwtest.s - OBERON_RISC5_FAST O7 debug: write SD block 80002H (FS sector 1 of an image at FSoffset 80000H; the
; user allowed overwriting the card) twice and read it back: (1) the 512 data bytes sent slowly, one byte per
; SPI transfer; (2) fast, 128 words (as the monitor's s and Wirth's Kernel.WriteSD). Prints per try: the data
; response byte, the busy count, the first 2 words read back and the number of different words.
; build/sdwtest.s = this + the monitor's SD / print routines (tools/mksdw.py); load with r5load.py.
.equ BUF, 0x6000
        SUB  R14, R14, 4
        STR  R15, R14, 0
        MOV  R10, -64
        BL   sdinit
        MOV  R2, R1
        PUTS 'init '
        BL   phex
        BL   crlf
        MOV  R4, 9             ; CMD9: the CSD (16 bytes after token FEH); bit 13 = perm., 12 = temp. write protect
        MOV  R5, 0
        BL   sdcmd
        MOV  R2, R1
        PUTS 'cmd9 '
        BL   phex
        MOV  R6, 0
c9t:    MOV  R1, 255
        BL   spi
        SUB  R3, R1, 0xFE
        BEQ  c9d
        ADD  R6, R6, 1
        SUB  R3, R6, 1000
        BLT  c9t
c9d:    PUTS ' csd'
        MOV  R6, 4
c9w:    MOV  R8, 4             ; 4 words, first byte at the top
        MOV  R2, 0
c9b:    MOV  R1, 255
        BL   spi
        LSL  R2, R2, 8
        IOR  R2, R2, R1
        SUB  R8, R8, 1
        BNE  c9b
        MOV  R1, 32
        BL   putc
        BL   phex
        SUB  R6, R6, 1
        BNE  c9w
        BL   crlf
        MOV  R1, 0
        STR  R1, R10, 20
        MOV  R1, 255
        BL   spi
        MOV  R11, 0            ; try 0: slow, 1: fast
try:    MOV  R7, BUF           ; pattern: word i = i * 01010101H XOR (try + 1) * 11223344H
        MOV  R6, 0
tp:     MOVH R2, 0x0101
        IOR  R2, R2, 0x0101
        MUL  R2, R2, R6
        MOVH R3, 0x1122
        IOR  R3, R3, 0x3344
        ADD  R4, R11, 1
        MUL  R3, R3, R4
        XOR  R2, R2, R3
        STR  R2, R7, 0
        ADD  R7, R7, 4
        ADD  R6, R6, 1
        SUB  R3, R6, 128
        BNE  tp
        MOV  R4, 24
        MOVH R5, 8
        IOR  R5, R5, 2
        BL   sdadr
        BL   sdcmd
        MOV  R2, R1
        PUTS 'cmd24 '
        BL   phex
        MOV  R1, 0xFE
        BL   spi
        MOV  R7, BUF
        SUB  R3, R11, 0
        BNE  wfast
        MOV  R6, 512           ; slow: bytes, LSByte of each word first
ws:     LDB  R1, R7, 0
        BL   spi
        ADD  R7, R7, 1
        SUB  R6, R6, 1
        BNE  ws
        B    wcrc
wfast:  MOV  R1, 5
        STR  R1, R10, 20
        MOV  R6, 128
wf:     LDR  R1, R7, 0
        BL   spi
        ADD  R7, R7, 4
        SUB  R6, R6, 1
        BNE  wf
        MOV  R1, 1
        STR  R1, R10, 20
wcrc:   MOV  R1, 255
        BL   spi
        MOV  R1, 255
        BL   spi
        MOV  R6, 0
wr:     MOV  R1, 255
        BL   spi
        AND  R3, R1, 0x10
        BEQ  wr1               ; a data response has bit 4 = 0
        ADD  R6, R6, 1
        SUB  R3, R6, 100
        BLT  wr
wr1:    MOV  R2, R1
        PUTS ' resp '
        BL   phex
        MOV  R6, 0
wb:     MOV  R1, 255
        BL   spi
        ADD  R6, R6, 1
        SUB  R3, R1, 255
        BEQ  wb1
        MOVH R3, 0x10
        SUB  R3, R6, R3
        BLT  wb
wb1:    MOV  R1, 0
        STR  R1, R10, 20
        MOV  R1, 255
        BL   spi
        MOV  R2, R6
        PUTS ' busy '
        BL   phex
        MOV  R4, 13            ; CMD13: R2 = R1 + status byte (bit 0 locked, 1 WP erase skip, 2 error, 3 CC,
        MOV  R5, 0             ; 4 ECC, 5 WP violation, 6 erase param, 7 out of range)
        BL   sdcmd
        MOV  R2, R1
        MOV  R1, 255
        BL   spi
        LSL  R2, R2, 8
        IOR  R2, R2, R1
        PUTS ' st '
        BL   phex
        MOV  R1, 0
        STR  R1, R10, 20
        MOV  R1, 255
        BL   spi
        MOVH R9, 8
        IOR  R9, R9, 2
        MOV  R7, 0x6400
        BL   sdread
        MOV  R2, R1
        PUTS ' rd '
        BL   phex
        MOV  R7, 0x6400
        LDR  R2, R7, 0
        PUTS ' w0 '
        BL   phex
        LDR  R2, R7, 4
        PUTS ' w1 '
        BL   phex
        MOV  R7, BUF
        MOV  R6, 128
        MOV  R8, 0
wc:     LDR  R1, R7, 0
        LDR  R2, R7, 0x400
        SUB  R3, R1, R2
        BEQ  wc1
        ADD  R8, R8, 1
wc1:    ADD  R7, R7, 4
        SUB  R6, R6, 1
        BNE  wc
        MOV  R2, R8
        PUTS ' diff '
        BL   phex
        BL   crlf
        ADD  R11, R11, 1
        SUB  R3, R11, 2
        BNE  try
        LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15
