; sdtest.s - OBERON_RISC5_FAST O4: wake the microSD card in SPI mode and READ sector 0 (nothing is written: this
; program has no write command). Loaded with tools/r5load.py (4000H), run with g. Wirth's SPI (I/O words 4, 5):
; data at FFFFD0H (a write starts a transfer), control/status at FFFFD4H (write: bit 0 = select the card,
; bit 2 = fast = 32-bit words, LSByte first; read: bit 0 = ready). The steps follow Wirth's BootLoad/Kernel:
;   80 clocks deselected, CMD0 (idle), CMD8 1AAH (v2 card), CMD55 + ACMD41 with HCS until ready, CMD58 (OCR,
;   bit 30 = SDHC/SDXC: block addresses), CMD16 512, CMD17 0, token FEH, 128 words fast, 2 CRC bytes.
; Prints one line per step (cmd0 01, cmd8 01 000001AA, acmd41 00 <tries>, ocr <ocr> sdhc, cmd16 00), then
; 'sector 0' and the 512 bytes (32 lines 'OOO: bb .. bb'), 'sig <bytes 510, 511>' (55AA = MBR / boot sector),
; 'sd ok'. A step that fails prints its line and then 'sd err'.
; Keeps R10 (I/O base), R11, R14 (stack); returns with B R15.
.equ BUF, 0x6000
        SUB  R14, R14, 4
        STR  R15, R14, 0
        PUTS 'sd'
        BL   crlf
        MOV  R1, 0               ; deselected, slow: 80 clocks (the card's power-up)
        STR  R1, R10, 20
        MOV  R6, 10
pw:     MOV  R1, 255
        BL   spi
        SUB  R6, R6, 1
        BNE  pw
        ; CMD0: go idle (SPI mode)
        MOV  R4, 0
        MOV  R5, 0
        BL   cmd
        MOV  R6, R1
        PUTS 'cmd0 '
        MOV  R2, R6
        BL   phex2
        BL   crlf
        SUB  R3, R6, 1
        BNE  err
        ; CMD8: interface condition (v2 card, 2.7-3.6 V, check pattern AAH)
        MOV  R4, 8
        MOV  R5, 0x1AA
        BL   cmd
        MOV  R6, R1
        BL   rd4
        PUTS 'cmd8 '
        MOV  R2, R6
        BL   phex2
        MOV  R1, 32
        BL   putc
        MOV  R2, R7
        BL   phex
        BL   crlf
        SUB  R3, R6, 1
        BNE  err
        AND  R3, R7, 0xFFF
        SUB  R3, R3, 0x1AA
        BNE  err
        ; CMD55 + ACMD41 (HCS) until the card leaves idle
        MOV  R8, 0
ac:     ADD  R8, R8, 1
        MOV  R4, 55
        MOV  R5, 0
        BL   cmd
        MOV  R4, 41
        MOVH R5, 0x4000
        BL   cmd
        MOV  R6, R1
        SUB  R3, R6, 0
        BEQ  acx
        SUB  R3, R8, 4000
        BLT  ac
acx:    PUTS 'acmd41 '
        MOV  R2, R6
        BL   phex2
        MOV  R1, 32
        BL   putc
        MOV  R2, R8
        BL   pdec
        BL   crlf
        SUB  R3, R6, 0
        BNE  err
        ; CMD58: OCR
        MOV  R4, 58
        MOV  R5, 0
        BL   cmd
        MOV  R6, R1
        BL   rd4
        PUTS 'ocr '
        MOV  R2, R7
        BL   phex
        LSL  R3, R7, 1           ; bit 30 -> sign
        BMI  hc
        PUTS ' sdsc'
        B    hcx
hc:     PUTS ' sdhc'
hcx:    BL   crlf
        SUB  R3, R6, 0
        BNE  err
        ; CMD16: 512-byte blocks (SDHC ignores it, Wirth sends it)
        MOV  R4, 16
        MOVH R5, 0
        IOR  R5, R5, 512
        BL   cmd
        MOV  R6, R1
        PUTS 'cmd16 '
        MOV  R2, R6
        BL   phex2
        BL   crlf
        SUB  R3, R6, 0
        BNE  err
        ; CMD17: read sector 0 (address 0 for both block and byte addressing)
        MOV  R4, 17
        MOV  R5, 0
        BL   cmd
        MOV  R6, R1
        SUB  R3, R6, 0
        BNE  e17
        MOV  R8, 0
tk:     MOV  R1, 255             ; wait for the data token FEH
        BL   spi
        SUB  R3, R1, 0xFE
        BEQ  tok
        ADD  R8, R8, 1
        SUB  R3, R8, 10000
        BLT  tk
        MOV  R6, R1
        B    e17
tok:    MOV  R1, 5               ; selected + fast: 128 words
        STR  R1, R10, 20
        MOV  R8, BUF
        MOV  R6, 128
rw:     MOV  R1, -1
        BL   spi
        STR  R1, R8, 0
        ADD  R8, R8, 4
        SUB  R6, R6, 1
        BNE  rw
        MOV  R1, 1               ; slow: the 2 CRC bytes
        STR  R1, R10, 20
        MOV  R1, 255
        BL   spi
        MOV  R1, 255
        BL   spi
        MOV  R1, 0               ; deselect, one more byte of clocks
        STR  R1, R10, 20
        MOV  R1, 255
        BL   spi
        ; dump
        PUTS 'sector 0'
        BL   crlf
        MOV  R8, 0
dl:     MOV  R2, R8
        MOV  R13, 3
        BL   phexn
        MOV  R1, ':'
        BL   putc
        MOV  R6, 16
db:     MOV  R1, 32
        BL   putc
        MOV  R3, BUF
        ADD  R3, R3, R8
        LDB  R2, R3, 0
        BL   phex2
        ADD  R8, R8, 1
        SUB  R6, R6, 1
        BNE  db
        BL   crlf
        SUB  R3, R8, 512
        BLT  dl
        MOV  R3, BUF
        LDB  R1, R3, 510
        LDB  R2, R3, 511
        LSL  R1, R1, 8
        IOR  R6, R2, R1
        PUTS 'sig '
        MOV  R2, R6
        MOV  R13, 4
        BL   phexn
        BL   crlf
        PUTS 'sd ok'
        BL   crlf
        B    done
e17:    PUTS 'cmd17 '
        MOV  R2, R6
        BL   phex2
        BL   crlf
err:    PUTS 'sd err'
        BL   crlf
        MOV  R1, 0
        STR  R1, R10, 20
done:   LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15

; ---- SPI ----
; spi: send R1 (slow: its low byte; fast: the word), wait, R1 := the received byte / word. Uses R3.
spi:    STR  R1, R10, 16
sw:     LDR  R3, R10, 20
        AND  R3, R3, 1
        BEQ  sw
        LDR  R1, R10, 16
        B    R15
; cmd: command R4 with argument R5 (Wirth's SPICmd), R1 := R1 response (< 80H), or FFH after 32 bytes.
; The card stays selected (slow) for the bytes that follow. Uses R1, R2, R3.
cmd:    SUB  R14, R14, 4
        STR  R15, R14, 0
        MOV  R1, 0
        STR  R1, R10, 20
        MOV  R1, 255
        BL   spi
        MOV  R1, 1
        STR  R1, R10, 20
        MOV  R2, 0
cw:     MOV  R1, 255             ; until the card is not busy
        BL   spi
        SUB  R3, R1, 255
        BEQ  cs
        ADD  R2, R2, 1
        SUB  R3, R2, 10000
        BLT  cw
cs:     IOR  R1, R4, 0x40
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
        BNE  c8
        MOV  R1, 0x95
c8:     SUB  R3, R4, 8
        BNE  cc
        MOV  R1, 0x87
cc:     BL   spi
        MOV  R2, 32
cr:     MOV  R1, 255
        BL   spi
        SUB  R3, R1, 0x80
        BLT  cx
        SUB  R2, R2, 1
        BNE  cr
cx:     LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15
; rd4: R7 := the next 4 bytes, first byte highest. Uses R1, R3, R13.
rd4:    SUB  R14, R14, 4
        STR  R15, R14, 0
        MOV  R7, 0
        MOV  R13, 4
r4l:    MOV  R1, 255
        BL   spi
        LSL  R7, R7, 8
        IOR  R7, R7, R1
        SUB  R13, R13, 1
        BNE  r4l
        LDR  R15, R14, 0
        ADD  R14, R14, 4
        B    R15

; ---- output (copies of the monitor's, phexn added) ----
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
; phex: R2 as 8 hex digits; phex2: its low 2; phexn: its low R13 (1..8). Uses R1, R2, R3, R12, R13.
phex:   MOV  R13, 8
        B    phexn
phex2:  MOV  R13, 2
phexn:  SUB  R14, R14, 4
        STR  R15, R14, 0
        LSL  R3, R13, 2
        MOV  R12, 32
        SUB  R12, R12, R3
        LSL  R2, R2, R12         ; 32 - 4n (n = 8: 0, shifts use 5 bits)
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
