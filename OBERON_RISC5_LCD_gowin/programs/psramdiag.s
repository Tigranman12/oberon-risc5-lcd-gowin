; psramdiag.s - OBERON_RISC5_FAST O6 debug: where do PSRAM / cache errors come from? Writes the psramtest
; pattern to 100000H + 4i (i < n), skipping the lines whose cache index is this program's (4000H-43FFH), its
; counters and log (1000H-13FFH) or the stack (7E00H-7FFFH), so its own code is never refetched; then reads it
; back twice. Per pass: 'pass p: e0 .. e7' = errors per word position in the line, then the first 10 errors
; 'adr read want' (read = a second load of the word, a cache hit). The same address and value in both passes = stored wrong (write); else read errors.
.equ NWH, 0xC
.equ NWL, 0
.equ EC, 0x1180
.equ LG, 0x1200
        SUB  R14, R14, 4
        STR  R15, R14, 0
        MOVH R8, 0x10
        MOVH R7, 0x9E37
        IOR  R7, R7, 0x79B1
        MOVH R5, NWH
        IOR  R5, R5, NWL
        MOV  R6, 0
wl:     BL   skip
        BNE  wn
        MUL  R1, R6, R7
        ADD  R1, R1, R6
        LSL  R2, R6, 2
        ADD  R2, R2, R8
        STR  R1, R2, 0
wn:     ADD  R6, R6, 1
        SUB  R3, R6, R5
        BNE  wl
        MOV  R9, 1             ; pass
pass:   MOV  R2, 0             ; clear the counters: 8 positions, the log count
        MOV  R3, EC
        MOV  R4, 9
clr:    STR  R2, R3, 0
        ADD  R3, R3, 4
        SUB  R4, R4, 1
        BNE  clr
        MOV  R6, 0
rl:     BL   skip
        BNE  rok
        MUL  R1, R6, R7
        ADD  R1, R1, R6
        LSL  R2, R6, 2
        ADD  R2, R2, R8
        LDR  R4, R2, 0
        SUB  R3, R4, R1
        BEQ  rok
        AND  R3, R6, 7         ; count at position i mod 8
        LSL  R3, R3, 2
        ADD  R3, R3, EC
        LDR  R12, R3, 0
        ADD  R12, R12, 1
        STR  R12, R3, 0
        MOV  R3, EC            ; log the first 10: adr, read, want
        LDR  R12, R3, 32
        SUB  R13, R12, 100
        BGE  rok
        ADD  R13, R12, 1
        STR  R13, R3, 32
        MOV  R13, 12
        MUL  R12, R12, R13
        ADD  R12, R12, LG
        STR  R2, R12, 0
        LDR  R4, R2, 0         ; read again (a hit now): the word in the cache
        STR  R4, R12, 4
        STR  R1, R12, 8
rok:    ADD  R6, R6, 1
        SUB  R3, R6, R5
        BNE  rl
        PUTS 'pass '
        MOV  R2, R9
        BL   phex
        PUTS ':'
        MOV  R4, EC
        MOV  R12, 8
pl:     MOV  R1, 32
        BL   putc
        LDR  R2, R4, 0
        BL   phex
        ADD  R4, R4, 4
        SUB  R12, R12, 1
        BNE  pl
        BL   crlf
        MOV  R4, LG            ; the log
        MOV  R3, EC
        LDR  R12, R3, 32
        SUB  R3, R12, 0
        BEQ  lx
ll:     LDR  R2, R4, 0
        BL   phex
        MOV  R1, 32
        BL   putc
        LDR  R2, R4, 4
        BL   phex
        MOV  R1, 32
        BL   putc
        LDR  R2, R4, 8
        BL   phex
        BL   crlf
        ADD  R4, R4, 12
        SUB  R12, R12, 1
        BNE  ll
lx:     ADD  R9, R9, 1
        SUB  R3, R9, 3
        BNE  pass
        PUTS 'cache '
        LDR  R2, R10, 36
        BL   phex
        MOV  R1, 32
        BL   putc
        LDR  R2, R10, 40
        BL   phex
        BL   crlf
        LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15
; skip: Z clear (NE) if word i (R6) at 100000H + 4i has a cache index (bits 14:5) in 80H-BFH, 200H-21FH, 3F0H-3FFH.
; Uses R3, R13.
skip:   ASR  R3, R6, 3
        AND  R3, R3, 0x3FF
        SUB  R13, R3, 0x3F0
        BGE  sk1
        SUB  R13, R3, 0x200
        BLT  sk2
        SUB  R13, R3, 0x220
        BLT  sk1
sk0:    MOV  R13, 0            ; Z set: test this word
        SUB  R13, R13, 0
        B    R15
sk2:    SUB  R13, R3, 0x80
        BLT  sk0
        SUB  R13, R3, 0xC0
        BGE  sk0
sk1:    MOV  R13, 1            ; Z clear: skip
        SUB  R13, R13, 0
        B    R15
; ---- the monitor's routines (copies: a loaded program has its own)
putc:   LDR  R3, R10, 12
        AND  R3, R3, 2
        BEQ  putc
        STR  R1, R10, 8
        B    R15
crlf:   SUB  R14, R14, 4
        STR  R15, R14, 0
        MOV  R1, 13
        BL   putc
        MOV  R1, 10
        BL   putc
        LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15
phex:   SUB  R14, R14, 4
        STR  R15, R14, 0
        MOV  R13, 8
phl:    ROR  R2, R2, 28
        AND  R1, R2, 15
        SUB  R3, R1, 10
        BLT  phd
        ADD  R1, R1, 7
phd:    ADD  R1, R1, '0'
        BL   putc
        SUB  R13, R13, 1
        BNE  phl
        LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15
