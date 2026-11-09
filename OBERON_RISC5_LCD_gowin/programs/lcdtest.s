; lcdtest.s - OBERON_RISC5_LCD_gowin L1: a test picture in the LCD frame memory (rtl/r5_lcd.v, 400000H,
; 480 x 272, Span 60 bytes; pixel (x, y) = bit x MOD 32 of the word at 400000H + y * 60 + (x DIV 32) * 4,
; y = 0 is the BOTTOM line, as Wirth's Display.Mod). Loaded with tools/r5load.py (4000H), run with g.
; On the panel (white on black):
;   - a border around the whole screen (lines y = 0 and y = 271, columns x = 0 and x = 479);
;   - a filled 32 x 32 square in the BOTTOM-LEFT corner (Oberon's (0, 0): proves the y flip and the bit order);
;   - a diagonal x = y from there up to the right (y = 0..271);
;   - an 8 x 8 block at x 440..447, y 256..263 (near the top-right), written with byte stores (STB).
; Prints 'lcd ok'. Keeps R10 (I/O base), R11, R14 (stack); returns with B R15.
        MOV  R13, R15          ; return address to the monitor
        MOVH R8, 0x40          ; frame base 400000H
; clear the 4080 words (272 lines x 15)
        MOV  R1, 0
        MOV  R2, 0
clr:    ADD  R4, R8, R2
        STR  R1, R4, 0
        ADD  R2, R2, 4
        SUB  R3, R2, 16320
        BLT  clr
; lines y = 0 and y = 271 (at 271 * 60 = 16260)
        MOV  R1, -1
        MOV  R2, 0
hl:     ADD  R4, R8, R2
        STR  R1, R4, 0
        STR  R1, R4, 16260
        ADD  R2, R2, 4
        SUB  R3, R2, 60
        BLT  hl
; columns x = 0 (word 0, bit 0) and x = 479 (word 14, bit 31) on every line
        MOVH R5, 0x8000        ; bit 31
        MOV  R2, 0             ; y * 60
vl:     ADD  R4, R8, R2
        LDR  R1, R4, 0
        IOR  R1, R1, 1
        STR  R1, R4, 0
        LDR  R1, R4, 56
        IOR  R1, R1, R5
        STR  R1, R4, 56
        ADD  R2, R2, 60
        SUB  R3, R2, 16320
        BLT  vl
; the 32 x 32 square at (0, 0): word 0 of lines 0..31
        MOV  R1, -1
        MOV  R2, 0
sq:     ADD  R4, R8, R2
        STR  R1, R4, 0
        ADD  R2, R2, 60
        SUB  R3, R2, 1920
        BLT  sq
; the diagonal: pixel (y, y), word y * 15 + y DIV 32, bit y MOD 32
        MOV  R6, 0             ; y
dg:     MUL  R4, R6, 60
        ASR  R1, R6, 5
        LSL  R1, R1, 2
        ADD  R4, R4, R1
        ADD  R4, R4, R8
        AND  R1, R6, 31
        MOV  R2, 1
        LSL  R2, R2, R1
        LDR  R1, R4, 0
        IOR  R1, R1, R2
        STR  R1, R4, 0
        ADD  R6, R6, 1
        SUB  R3, R6, 272
        BLT  dg
; the 8 x 8 block with byte stores: byte 55 (x 440..447) of lines 256..263
        MOV  R1, 255
        MOV  R6, 256
bb:     MUL  R4, R6, 60
        ADD  R4, R4, R8
        STB  R1, R4, 55
        ADD  R6, R6, 1
        SUB  R3, R6, 264
        BLT  bb
        PUTS 'lcd ok\r\n'
        MOV  R15, R13
        B    R15
; putc: send R1 (uses R3)
putc:   LDR  R3, R10, 12
        AND  R3, R3, 2         ; rdyTx
        BEQ  putc
        STR  R1, R10, 8
        B    R15
