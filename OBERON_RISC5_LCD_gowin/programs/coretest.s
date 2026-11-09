; coretest.s - OBERON_RISC5_FAST O8: a stand-in for Oberon's inner core, for tb_mon. tools/mkcore.py assembles it
; (at address 0), puts its size at address 16 (word 4, as Wirth's linker: the end of the inner core) and appends a table
; up to that size, and writes it as the SD model's image at block 80004H. The monitor's 'o' loads it to 0, puts
; MemLim / stackOrg at 12 / 24, sets SP and MT and jumps to 0. It prints
;   core <mem 12> <mem 24> <R12> <R14> <sum of the words from 100H to the end> <the 4 words at 0E7F00H (L2)>
; and stops (loops). Words 1-31 are fillers (addresses 12, 16, 24: written by mkcore / the monitor).
        B    start
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
        MOV  R0, R0
start:  MOV  R5, R12           ; word 32
        MOV  R6, R14
        MOV  R10, -64
        PUTS 'core '
        MOV  R9, 0
        LDR  R2, R9, 12
        BL   phex
        MOV  R1, 32
        BL   putc
        LDR  R2, R9, 24
        BL   phex
        MOV  R1, 32
        BL   putc
        MOV  R2, R5
        BL   phex
        MOV  R1, 32
        BL   putc
        MOV  R2, R6
        BL   phex
        MOV  R1, 32
        BL   putc
        MOV  R7, 0             ; sum of the words 100H .. end
        MOV  R8, 0x100
        LDR  R4, R9, 16
sl:     LDR  R1, R8, 0
        ADD  R7, R7, R1
        ADD  R8, R8, 4
        SUB  R3, R8, R4
        BLT  sl
        MOV  R2, R7
        BL   phex
        MOVH R8, 0xE           ; L2: the 4 Display words the monitor put at 0E7F00H
        IOR  R8, R8, 0x7F00
        MOV  R1, 32
        BL   putc
        LDR  R2, R8, 0
        BL   phex
        MOV  R1, 32
        BL   putc
        LDR  R2, R8, 4
        BL   phex
        MOV  R1, 32
        BL   putc
        LDR  R2, R8, 8
        BL   phex
        MOV  R1, 32
        BL   putc
        LDR  R2, R8, 12
        BL   phex
        MOV  R1, 13
        BL   putc
        MOV  R1, 10
        BL   putc
hang:   B    hang
putc:   LDR  R3, R10, 12
        AND  R3, R3, 2
        BEQ  putc
        STR  R1, R10, 8
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
