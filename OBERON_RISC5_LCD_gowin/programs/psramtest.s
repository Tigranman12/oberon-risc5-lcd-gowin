; psramtest.s - OBERON_RISC5_FAST O3: test of the PSRAM (O6: 100000H-3FFFFFH, 3 MB; 0-FFFFFH holds the
; monitor's buffers, stack and the program), loaded with
; tools/r5load.py (4000H) and run with g. Prints, one item per line:
;   psram <status>       r5_psram's status (I/O word 8): 8xxx.... = ready, then err_to, err_lat, RWDS in CA;
;                        bits 23-16 = the data cycle it measured, 15-0 = transactions so far
;   ok <n> words         every word i of n got i * 9E3779B1H + i written and read back (an address that is
;                        stuck or tied to another one breaks the pattern); else 'bad <address> <read> <want>'
;   bytes ok             STB to each lane of word 0, then LDR and LDB (else 'bytes bad <read>')
;   ms <t>               time of the write and read passes, decimal
;   psram <status>       again (transactions counted)
;   cache <misses> <wb>  O5: r5_cache's counters (I/O words 9, 10)
; NWH:NWL = number of words (O6: C0000H = 3 MB; run_rf.sh makes a short copy for the simulation).
; Keeps R10 (I/O base), R11, R14 (stack); returns with B R15.
.equ NWH, 0xC
.equ NWL, 0
        SUB  R14, R14, 4
        STR  R15, R14, 0
        PUTS 'psram '
        LDR  R2, R10, 32       ; FFFFE0H: status
        BL   phex
        BL   crlf
        MOVH R8, 0x10          ; O6: 100000H (O3: 400000H; below: the monitor, programs)
        MOVH R7, 0x9E37
        IOR  R7, R7, 0x79B1    ; 9E3779B1H
        MOVH R5, NWH
        IOR  R5, R5, NWL       ; n
        LDR  R9, R10, 0        ; ms at the start
        MOV  R6, 0
wl:     MUL  R1, R6, R7
        ADD  R1, R1, R6
        LSL  R2, R6, 2
        ADD  R2, R2, R8
        STR  R1, R2, 0
        ADD  R6, R6, 1
        SUB  R3, R6, R5
        BNE  wl
        MOV  R6, 0
rl:     MUL  R1, R6, R7
        ADD  R1, R1, R6
        LSL  R2, R6, 2
        ADD  R2, R2, R8
        LDR  R4, R2, 0
        SUB  R3, R4, R1
        BNE  bad
        ADD  R6, R6, 1
        SUB  R3, R6, R5
        BNE  rl
        LDR  R3, R10, 0
        SUB  R9, R3, R9        ; ms of both passes
        PUTS 'ok '
        MOV  R2, R5
        BL   phex
        PUTS ' words'
        BL   crlf
        ; bytes
        MOV  R1, -1
        STR  R1, R8, 0
        MOV  R1, 0x11
        STB  R1, R8, 0
        MOV  R1, 0x22
        STB  R1, R8, 1
        MOV  R1, 0x33
        STB  R1, R8, 2
        MOV  R1, 0x44
        STB  R1, R8, 3
        LDR  R4, R8, 0
        MOVH R1, 0x4433
        IOR  R1, R1, 0x2211
        SUB  R3, R4, R1
        BNE  badb
        LDB  R4, R8, 2
        SUB  R3, R4, 0x33
        BNE  badb
        PUTS 'bytes ok'
        BL   crlf
        PUTS 'ms '
        MOV  R2, R9
        BL   pdec
        BL   crlf
        PUTS 'psram '
        LDR  R2, R10, 32
        BL   phex
        BL   crlf
        PUTS 'cache '          ; O5: misses (lines filled), write-backs
        LDR  R2, R10, 36
        BL   phex
        MOV  R1, 32
        BL   putc
        LDR  R2, R10, 40
        BL   phex
        BL   crlf
        B    done
bad:    MOV  R5, R1            ; want
        PUTS 'bad '
        BL   phex              ; R2 = address
        MOV  R1, 32
        BL   putc
        MOV  R2, R4
        BL   phex
        MOV  R1, 32
        BL   putc
        MOV  R2, R5
        BL   phex
        BL   crlf
        B    done
badb:   PUTS 'bytes bad '
        MOV  R2, R4
        BL   phex
        BL   crlf
done:   LDR  R15, R14, 0
        ADD  R14, R14, 4
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
pdec:   SUB  R14, R14, 4
        STR  R15, R14, 0
        MOV  R12, 0x1100
        MOV  R13, 0
pdl:    DIV  R3, R2, 10
        MUL  R1, R3, 10
        SUB  R1, R2, R1
        ADD  R1, R1, '0'
        ADD  R4, R12, R13
        STB  R1, R4, 0
        ADD  R13, R13, 1
        MOV  R2, R3
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
