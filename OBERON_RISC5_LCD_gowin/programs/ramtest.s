; ramtest.s - OBERON_RISC5_FAST F1: a program that runs from the RAM (not the boot ROM), to test RISC5F's
; instruction fetch from the rising-edge RAM (PLAN.md F-D3): loads right after fetches, a store-load pair,
; byte loads/stores, MUL and DIV stalls (the RAM re-reads during a stall), a call inside the RAM.
; Loaded at 3000H (tb_mon.v preloads it; on the board it can be typed with the monitor's w), run with g 3000.
; Branches are PC-relative, so it runs at any address. Results (check with d 2000, d 2010):
;   2000: 000013BA (100+99+..+1)   2004: 807ECFC1 (the b 100 checksum)   2008: 00173C44 (1234*1234)
;   200C: 000351C0 (1522756 DIV 7)  2010: 77555504 (bytes: remainder 4, 55, 55 loaded back, 77 from the call)
; Keeps R10, R11, R14 (the monitor's); returns with B R15.
        MOV  R13, R15          ; return address to the monitor
        MOV  R8, 0x2000
        MOV  R6, 100
        MOV  R7, 0
        STR  R7, R8, 0
loop:   LDR  R1, R8, 0
        ADD  R1, R1, R6
        XOR  R7, R7, R1
        ROR  R7, R7, 3
        STR  R1, R8, 0
        SUB  R6, R6, 1
        BNE  loop
        STR  R7, R8, 4
        MOV  R1, 1234
        MUL  R2, R1, R1
        STR  R2, R8, 8
        DIV  R3, R2, 7
        GETH R4
        STR  R3, R8, 12
        STB  R4, R8, 16
        MOV  R1, 0x55
        STB  R1, R8, 17
        LDB  R5, R8, 17
        STB  R5, R8, 18
        BL   sub
        STB  R1, R8, 19
        MOV  R15, R13
        B    R15
sub:    MOV  R1, 0x77
        B    R15
