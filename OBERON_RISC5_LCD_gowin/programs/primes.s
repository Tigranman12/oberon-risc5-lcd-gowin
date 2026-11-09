; primes.s - OBERON_RISC5_FAST O2 demo: sent over the serial line by tools/r5load.py (default address 4000H)
; and run by the monitor's g; prints the primes below 100 (trial division with MUL and DIV), then returns.
; Branches are PC-relative, so it runs at any address. Keeps R10 (I/O base), R11, R14 (stack); returns with B R15.
        MOV  R13, R15          ; return address to the monitor
        PUTS 'primes from RAM:'
        MOV  R6, 2             ; n
pn:     MOV  R7, 2             ; d
pd:     MUL  R1, R7, R7
        SUB  R3, R1, R6
        BGT  pprime            ; d * d > n: n is prime
        DIV  R1, R6, R7
        GETH R1                ; n MOD d
        SUB  R3, R1, 0
        BEQ  pnext
        ADD  R7, R7, 1
        B    pd
pprime: MOV  R1, 32
        BL   putc
        MOV  R2, R6
        BL   pdec2
pnext:  ADD  R6, R6, 1
        SUB  R3, R6, 100
        BLT  pn
        MOV  R1, 13
        BL   putc
        MOV  R1, 10
        BL   putc
        MOV  R15, R13
        B    R15

; putc: send R1 (uses R3)
putc:   LDR  R3, R10, 12
        AND  R3, R3, 2         ; rdyTx
        BEQ  putc
        STR  R1, R10, 8
        B    R15

; pdec2: R2 (0..99) in decimal (uses R1, R3, R4, R12)
pdec2:  SUB  R14, R14, 4
        STR  R15, R14, 0
        DIV  R3, R2, 10
        GETH R4
        SUB  R12, R3, 0
        BEQ  pd1
        ADD  R1, R3, '0'
        BL   putc
pd1:    ADD  R1, R4, '0'
        BL   putc
        LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15
