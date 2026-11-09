`timescale 1ns/1ps
// tb_mon.v - OBERON_RISC5_FAST (copied from OBERON_RISC5 S2b; F0 adds the speed test 'b'): programs/monitor.s in the boot ROM of r5_tang, driven by a terminal
// model that types commands like PuTTY. Checks memory write/read/dump, the ms timer, MUL (+H), DIV/MOD (+H),
// the floating-point units (FLT, FAD, FML, FDV, FLOOR), help, unknown command, Backspace, the speed loop 'b',
// and (F1) programs/ramtest.s run FROM THE RAM with 'g 3000' (preloaded from build/ramtest.mem at 3000H).
// O2: 'l' loads programs/primes.s at 4000H over the UART (build/load_primes.hex, Wirth's LoadFromLine
// format), the board's sum must equal tools/r5load.py's, then 'g 4000' prints the primes below 100.
// O5: 'l' stores primes.s twice on the same cache lines (O6: 10000H, 18000H) and runs both from the PSRAM cache;
// O6: all memory is the PSRAM model (4 MB) through the 32 KB cache; ramtest.s is preloaded there at 3000H;
// the cache counters (misses, write-backs) at FFFFE4H, FFFFE8H. Options: +o5 (only O3, O5), +o5c (only O5),
// +tmo=<ms>, +hdbg (the HyperRAM model prints each transaction).
// O3: 'l' loads programs/psramtest.s (256 words) and 'g 4000' tests the PSRAM through r5_psram and
// tb/hyperram_model.v (latency 6, fixed): its output lines and no protocol violations in the model.
// O4: 'l' loads programs/sdtest.s and 'g 4000' wakes tb/sd_spi_model.v (an SDHC card, SPI mode) and reads sector 0:
// every step's answer, the 512 bytes in the dump, the signature, and no write command / protocol error in the model.
// Last lines: "RESULT: n/m" and "TB PASS" or "TB FAIL". Run: ./run_rf.sh (from build/, prom.mem).
module tb_mon;
    localparam CPB = 234;               // 27 MHz / 115200
    reg clk = 1'b0;
    always #18.5 clk = ~clk;            // 27 MHz

    reg  rx = 1'b1;                     // terminal -> board
    wire tx;                            // board -> terminal
    wire [5:0] led;
    reg  rst_n = 1'b0;

    // O3: the PSRAM controller's clock (not locked to clk) and a HyperRAM model on channel 0
    reg mclk = 1'b0, mrst = 1'b1;
    always #9.259 mclk = ~mclk;                     // 54 MHz
    initial begin #500 mrst = 1'b0; end
    wire pck, pcs_n, preset_n, prwds;
    wire [7:0] pdq;
    hyperram_model #(.LC(6), .FIXED(1), .TCKD(3.0), .AW(21)) hram (   // O6: all 4 MB
       .ck(pck), .cs_n(pcs_n), .reset_n(preset_n),
        .dq(pdq), .rwds(prwds));

    r5_tang dut (.clk(clk), .rst_n(rst_n), .uart_rx(rx), .uart_tx(tx), .led(led),
        .mclk(mclk), .mrst(mrst), .psram_ck(pck), .psram_cs_n(pcs_n), .psram_reset_n(preset_n),
        .psram_dq(pdq), .psram_rwds(prwds),
        .sd_sclk(sclk), .sd_mosi(mosi), .sd_cs_n(sd_cs_n), .sd_miso(miso),
        .lclk(clk), .lcd_clk(), .lcd_de(), .lcd_hsync(), .lcd_vsync(), .lcd_r(), .lcd_g(), .lcd_b());   // L1
    function [31:0] fw(input integer i);             // L1: word i of the LCD frame memory
        fw = {dut.lcd.m3[i], dut.lcd.m2[i], dut.lcd.m1[i], dut.lcd.m0[i]};
    endfunction
    // O4: an SD card on the SPI pins
    wire sclk, mosi, sd_cs_n, miso;
    sd_spi_model #(.ACMD41_BUSY(2)) sd (.sclk(sclk), .mosi(mosi), .cs_n(sd_cs_n), .miso(miso));

    // ---- terminal: receive lines ----
    localparam W = 8*100;
    reg [W-1:0] lines [0:255];
    integer     n = 0;
    reg [W-1:0] cur = 0;
    reg [7:0]   b;
    integer     i;
    always begin
        @(negedge tx);
        repeat (CPB / 2) @(posedge clk);
        for (i = 0; i < 8; i = i + 1) begin
            repeat (CPB) @(posedge clk);
            b[i] = tx;
        end
        repeat (CPB) @(posedge clk);
        if (b == 8'h0A) begin
            $display("TTY| %0s", cur);
            lines[n] = cur;
            n = n + 1;
            cur = 0;
        end else if (b == 8'h08) cur = cur >> 8;     // Backspace moves the cursor back, like PuTTY
        else if (b != 8'h0D) cur = {cur[W-9:0], b};
    end
    function has(input [W-1:0] want);
        integer k;
        begin
            has = 1'b0;
            for (k = 0; k < n; k = k + 1)
                if (lines[k] == want) has = 1'b1;
        end
    endfunction

    function hashead(input [W-1:0] want, input integer drop);   // a line = want + any `drop` characters
        integer k;
        begin
            hashead = 1'b0;
            for (k = 0; k < n; k = k + 1)
                if ((lines[k] >> (8 * drop)) == want) hashead = 1'b1;
        end
    endfunction

    // ---- terminal: send ----
    task send(input [7:0] c);
        integer k;
        begin
            rx = 1'b0;
            repeat (CPB) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                rx = c[k];
                repeat (CPB) @(posedge clk);
            end
            rx = 1'b1;
            repeat (CPB) @(posedge clk);
        end
    endtask
    task wait_chars(input integer k);   // time for k characters
        repeat (CPB * 10 * k) @(posedge clk);
    endtask

    integer pass = 0, total = 0;
    reg [31:0] core_end [0:0], core_sum [0:0];     // O8 (tools/mkcore.py)
    integer k8, t8;
    integer bk, kk, bad7;                          // O7
    reg [8*9-1:0] s7;
    reg     o5 = 1'b0;
    reg [31:0] m0, w0;
    task check(input ok, input [8*50-1:0] what);
        begin
            total = total + 1;
            if (ok === 1'b1) begin
                pass = pass + 1;
                $display("PASS: %0s", what);
            end else
                $display("FAIL: %0s", what);
        end
    endtask
    // Wirth's receiver keeps one byte: like a person, type only after the answer and the next prompt.
    task wait_prompt;
        begin
            wait_chars(3);                  // Enter's CR LF echo clears the typed line
            while (cur != "r5> ") wait_chars(1);
        end
    endtask
    task type_line(input [8*40-1:0] s);  // the characters of s, then Enter
        integer k;
        begin
            for (k = 39; k >= 0; k = k - 1)
                if (s[8*k +: 8] != 8'h00) send(s[8*k +: 8]);
            send(8'h0D);
            wait_prompt;
        end
    endtask
    function ends_ms(input integer dummy);   // a line "<digits> ms" was received
        integer k;
        begin
            ends_ms = 1'b0;
            for (k = 0; k < n; k = k + 1)
                if (lines[k][23:0] == " ms" && lines[k][31:24] >= "0" && lines[k][31:24] <= "9") ends_ms = 1'b1;
        end
    endfunction

    // The FPGA starts every flip-flop and the block RAM at 0; Wirth's UART is never reset (see tb_r5.v)
    reg [31:0] ramtest [0:63];
    reg [7:0]  ldf [0:4095];                           // O2: the load frame, made by tools/r5load.py
    reg [31:0] ldsum [0:0];
    reg [8*8-1:0] sumtxt;
    integer    ldn;
    task load_frame(input [8*24-1:0] ffile, input [8*24-1:0] sfile);   // the monitor's l, then the sum line
        begin
            for (ldn = 0; ldn < 4096; ldn = ldn + 1) ldf[ldn] = 8'hxx;
            $readmemh(ffile, ldf);
            $readmemh(sfile, ldsum);
            send("l"); send(8'h0D);
            wait_chars(3);                              // the echo 'l' CR LF
            for (ldn = 0; ldf[ldn] !== 8'hxx; ldn = ldn + 1) send(ldf[ldn]);   // binary, back to back
            wait_prompt;
            sumtxt = hex8(ldsum[0]);
        end
    endtask
    function [8*8-1:0] hex8(input [31:0] x);         // 8 hex digits, upper case as the monitor's phex
        integer k;
        reg [3:0] d;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                d = x[4*k +: 4];
                hex8[8*k +: 8] = (d < 10) ? 8'h30 + d : 8'h37 + d;
            end
        end
    endfunction
    initial begin : power_up
        integer k;
        dut.transmitter.run = 1'b0;  dut.transmitter.tick = 12'd0;  dut.transmitter.bitcnt = 4'd0;
        dut.receiver.Q0 = 1'b0;      dut.receiver.Q1 = 1'b0;        dut.receiver.run = 1'b0;
        dut.receiver.tick = 12'd0;   dut.receiver.bitcnt = 4'd0;    dut.receiver.stat = 1'b0;
        // O6: the memory is the PSRAM model (half-words; word w = half-words 2w (bits 15:0), 2w+1 (31:16)).
        // The real PSRAM starts with random data; here 0, as the block RAM was (the d test reads it).
        for (k = 0; k < (1 << 21); k = k + 1) hram.mem[k] = 16'd0;
        $readmemh("ramtest.mem", ramtest, 0, 63);     // run_rf.sh assembles programs/ramtest.s
        for (k = 0; k < 64; k = k + 1) begin           // at 3000H = half-word 1800H
            hram.mem[21'h1800 + 2 * k] = ramtest[k][15:0]; hram.mem[21'h1800 + 2 * k + 1] = ramtest[k][31:16];
        end
    end

    initial begin
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        wait_chars(40);
        check(has("RISC5 monitor, ? help") && cur == "r5> ", "banner, prompt");
        if ($test$plusargs("o9rsim")) begin            // O9r (tools/o9rsim.sh): Oberon itself from the RAM disk
            $readmemh("rd_img.hex", hram.mem, 21'h80000);  // the .dsk at 100000H (half-words)
            tracef = $fopen("o9r_trace.txt", "w");     // the PC of each instruction from the core's start on
            send("r"); send(8'h0D);
            wait (nstep >= maxstep);
            $fclose(tracef);
            $display("o9rsim: %0d instructions traced", nstep);
            $finish;
        end
        o5 = $test$plusargs("o5");                      // +o5: only the PSRAM / cache parts (O3, O5), faster
        if (!o5) begin
        type_line("w 100 12345678");
        check(has("r5> w 100 12345678") && has("12345678"), "w: write and read back");
        type_line("d 100");
        check(has("00000100: 12345678") && has("00000104: 00000000") && has("0000010C: 00000000"), "d: dump");
        type_line("t");
        check(ends_ms(0), "t: milliseconds");
        type_line("m 7 6");
        check(has("42 00000000"), "m 7 6 = 42");
        type_line("m 100000 100000");
        check(has("1410065408 00000002"), "m: 10^10, high word in H");
        type_line("m -3 5");
        check(has("-15 FFFFFFFF"), "m -3 5 = -15");
        type_line("v 100 7");
        check(has("14 2"), "v 100 7: 14 rest 2");
        type_line("v -7 2");
        check(has("-4 1"), "v -7 2: -4 rest 1 (Oberon DIV rounds down)");
        type_line("v 5 0");
        check(has("r5> v 5 0") && lines[n-1] == "?", "v by 0: error");
        type_line("f 3 4");
        check(has("7 12 750"), "f 3 4: 7 12 750");
        type_line("f -7 2");
        check(has("-5 -14 -3500"), "f -7 2: -5 -14 -3500");
        type_line("?");
        check(has("d a|w a v|t|m|v|f a b|b n|g a|l|o [fs]|s b n|r"), "help");
        type_line("b 100");                 // 100 rounds: 900 clocks = 0.03 ms at 27 MHz
        check(has("807ECFC1 0 ms") || has("807ECFC1 1 ms"), "b 100: checksum 807ECFC1");
        type_line("g 3000");
        check(lines[n-1] == "ok", "g 3000: ramtest.s runs from the RAM and returns");
        type_line("d 2000");
        check(has("00002000: 000013BA") && has("00002004: 807ECFC1"), "ramtest: load/store loop from the RAM");
        check(has("00002008: 00173C44") && has("0000200C: 000351C0"), "ramtest: MUL, DIV stalls from the RAM");
        type_line("d 2010");
        check(has("00002010: 77555504"), "ramtest: bytes, store-load, call inside the RAM");
        type_line("x");
        check(lines[n-1] == "?", "unknown command");
        send("m"); send(" "); send("9"); send(" "); send("8"); send(8'h08);
        wait_chars(4);                      // the monitor answers Backspace with 3 characters
        send("7"); send(8'h0D);
        wait_prompt;
        check(has("r5> m 9 7") && has("63 00000000"), "Backspace: m 9 7 = 63");
        // O2: serial loading
        load_frame("load_primes.hex", "load_primes_sum.hex");
        check(lines[n-1] == sumtxt, "l: sum of the loaded words = r5load.py's");
        type_line("g 4000");
        check(has("primes from RAM: 2 3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71 73 79 83 89 97")
              && lines[n-1] == "ok", "g 4000: the loaded program runs (primes)");
        $display("loaded %0d bytes, sum %0s", ldn, sumtxt);
        end
        // O3: PSRAM (O5: through the cache)
        if (!$test$plusargs("o5c")) begin              // +o5c: skip O3 too (only O5)
        load_frame("load_psram.hex", "load_psram_sum.hex");
        check(lines[n-1] == sumtxt, "l: psramtest.s loaded (sum)");
        type_line("g 4000");
        // O6: the monitor's stack and buffers are in the PSRAM too, so the counts are not 0 at the start
        check(hashead("psram 900E", 4), "PSRAM ready, data cycle 14 measured (LC 6 fixed)");
        check(has("ok 00000100 words") && has("bytes ok"), "PSRAM: 256 words at 100000H and the byte lanes");
        check(lines[n-1] == "ok" && hram.viol == 0, "PSRAM test returns, no model violation");
        end
        // O4: SD card, read only
        if (!o5) begin
        load_frame("load_sd.hex", "load_sd_sum.hex");
        check(lines[n-1] == sumtxt, "l: sdtest.s loaded (sum)");
        type_line("g 4000");
        check(has("cmd0 01") && has("cmd8 01 000001AA") && has("acmd41 00 3") && has("ocr C0FF8000 sdhc")
              && has("cmd16 00"), "SD: CMD0, CMD8, ACMD41 x3, OCR SDHC, CMD16");
        check(has("000: 03 0A 11 18 1F 26 2D 34 3B 42 49 50 57 5E 65 6C")
              && has("1F0: 93 9A A1 A8 AF B6 BD C4 CB D2 D9 E0 E7 EE 55 AA"), "SD: sector 0 read (fast words, byte order)");
        check(has("sig 55AA") && has("sd ok") && lines[n-1] == "ok", "SD: signature 55AA, sd ok, returns");
        check(sd.viol == 0 && sd.nrd == 1, "SD: 1 read, model: no write, no protocol error");
        end
        // L1 (OBERON_RISC5_LCD_gowin): the LCD frame memory at 400000H (rtl/r5_lcd.v); programs/lcdtest.s draws
        // the test picture: border, 32 x 32 square at (0, 0), diagonal x = y, an 8 x 8 STB block at byte 55, y 256..263
        if (!o5) begin
        type_line("w 400000 A5A5F00F");
        check(lines[n-1] == "A5A5F00F" && fw(0) == 32'hA5A5F00F, "L1: w 400000: frame memory written, read back");
        load_frame("load_lcd.hex", "load_lcd_sum.hex");
        check(lines[n-1] == sumtxt, "l: lcdtest.s loaded (sum)");
        type_line("g 4000");
        check(has("lcd ok") && lines[n-1] == "ok", "L1: lcdtest.s runs and returns");
        check(fw(0) == 32'hFFFFFFFF && fw(31 * 15) == 32'hFFFFFFFF && fw(32 * 15) == 32'h00000001
              && fw(4065) == 32'hFFFFFFFF && fw(4079) == 32'hFFFFFFFF, "L1: lcdtest: lines y 0, 271, square 32 x 32");
        check(fw(1500) == 32'h00000001 && fw(1503) == 32'h00000010 && fw(1514) == 32'h80000000,
              "L1: lcdtest: y 100: columns x 0, 479, diagonal x 100");
        check(fw(3853) == 32'hFF000000 && fw(3868) == 32'hFF000000 && fw(3958) == 32'hFF000000
              && fw(3973) == 32'h00000000 && fw(3974) == 32'h80000000, "L1: lcdtest: STB block, byte 55 of lines 256..263");
        type_line("d 400000");
        check(has("00400000: FFFFFFFF") && has("00400004: FFFFFFFF"), "L1: d 400000: loads from the frame memory");
        end
        // O5: code from the PSRAM. O6: primes.s is stored at 10000H, then at 18000H (32 KB apart: the same cache
        // lines, index 0-9; the second load evicts the first copy's dirty lines = write-backs); g 10000 then misses
        // on every line (fetches, write-backs of the 18000H copy, refills from the PSRAM), g 18000 the same the
        // other way (clean victims). Counted over each g: 10 misses + 10 write-backs, then 10 + 0.
        if (!$test$plusargs("o8only")) begin          // +o8only: skip O5 (only the O8 part after it)
        n = 0;
        load_frame("load_primes_p1.hex", "load_primes_p1_sum.hex");
        check(lines[n-1] == sumtxt, "l: primes.s at 10000H (sum)");
        load_frame("load_primes_p2.hex", "load_primes_p2_sum.hex");
        check(lines[n-1] == sumtxt, "l: primes.s at 18000H (sum)");
        n = 0; m0 = dut.nmiss; w0 = dut.nwb;
        type_line("g 10000");
        check(has("primes from RAM: 2 3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71 73 79 83 89 97")
              && lines[n-1] == "ok" && dut.nmiss - m0 == 10 && dut.nwb - w0 == 10,
              "g 10000: runs, 10 fetch misses + 10 write-backs");
        $display("g 10000: %0d misses, %0d write-backs", dut.nmiss - m0, dut.nwb - w0);
        n = 0; m0 = dut.nmiss; w0 = dut.nwb;
        type_line("g 18000");
        check(has("primes from RAM: 2 3 5 7 11 13 17 19 23 29 31 37 41 43 47 53 59 61 67 71 73 79 83 89 97")
              && lines[n-1] == "ok" && dut.nmiss - m0 == 10 && dut.nwb - w0 == 0,
              "g 18000: the conflicting copy, 10 misses, 0 wb");
        $display("g 18000: %0d misses, %0d write-backs", dut.nmiss - m0, dut.nwb - w0);
        type_line("d FFFFE0");
        check(hram.viol == 0, "PSRAM model: no violation");
        end
        // O7 (before O8: its 'o' leaves the monitor): 's 80011 2' writes 2 blocks sent over the serial line (as tools/sdwrite.py): '>' first, then per block 512
        // bytes -> CMD24, read back, '.'; the SD model (+sdwrite) keeps blocks 80010H-80013H.
        if ($test$plusargs("sdwrite")) begin
            n = 0; k8 = sd.nrd; s7 = "s 80011 2";
            for (kk = 8; kk >= 0; kk = kk - 1) send(s7[8*kk +: 8]);
            send(8'h0D);
            t8 = 0;
            while (cur[7:0] != ">" && t8 < 4000) begin wait_chars(1); t8 = t8 + 1; end
            for (bk = 0; bk < 2; bk = bk + 1) begin
                for (kk = 0; kk < 512; kk = kk + 1) send(((bk * 512 + kk) * 7 + bk + 1) & 255);
                if (bk == 0) begin
                    t8 = 0;
                    while (cur[7:0] != "." && t8 < 4000) begin wait_chars(1); t8 = t8 + 1; end
                end
            end
            wait_prompt;
            bad7 = 0;
            for (bk = 0; bk < 2; bk = bk + 1)
                for (kk = 0; kk < 512; kk = kk + 1)
                    if (sd.wmem[(bk + 1) * 512 + kk] !== (((bk * 512 + kk) * 7 + bk + 1) & 255)) bad7 = bad7 + 1;
            check(has(">..") && has("ok") && sd.nwr == 2 && sd.nrd - k8 == 2, "s 80011 2: 2 blocks written, read back, ok");
            check(bad7 == 0 && sd.wvalid == 4'b0110 && sd.viol == 0, "s: the card holds the bytes sent, no violation");
            $display("s: %0d writes, %0d reads, %0d bytes different", sd.nwr, sd.nrd - k8, bad7);
        end
        // O8: 'o' = Wirth's BootLoad.LoadFromDisk. With +sdimg the SD model holds programs/coretest.s (tools/mkcore.py)
        // as the inner core at block 80004H. 'o 100000' finds no boot image (pattern data) and stays in the monitor;
        // 'o' loads the 4 blocks to 0 and jumps there: coretest prints MemLim, stackOrg, MT, SP and the table's sum.
        if ($test$plusargs("sdimg")) begin
            $readmemh("core_end.hex", core_end); $readmemh("core_sum.hex", core_sum);
            n = 0; k8 = sd.nrd;
            type_line("o 100000");
            check(has("no boot image") && cur == "r5> " && sd.nrd - k8 == 1, "o 100000: 1 block read, no boot image, r5>");
            n = 0; k8 = sd.nrd;
            if ($test$plusargs("o9r")) begin              // O9r: the core via l at 100400H (RAM disk), then r
                load_frame("load_rdcore.hex", "load_rdcore_sum.hex");
                check(lines[n-1] == sumtxt, "l: core frame at 100400H, sum");
                n = 0; k8 = sd.nrd;
                send("r");
            end else send("o");
            send(8'h0D);
            t8 = 0;
            while (!hashead("core ", 80) && !has("no boot image") && !has("sd err") && t8 < 8000) begin wait_chars(1); t8 = t8 + 1; end
            check(has({"oberon ", hex8(core_end[0])}), "o: boot image found, end printed");
            check(has({"core 000E7EF0 00080000 00000020 00080000 ", hex8(core_sum[0]), " 53697A67 000001E0 00000110 00400000"}),
                  "o: inner core runs: MemLim, stackOrg, MT, SP, sum, Display words (L2)");
            if ($test$plusargs("o9r")) check(sd.nrd == k8 && sd.viol == 0, "r: no SD block read");
            else check(sd.nrd - k8 == (core_end[0] + 511) / 512 && sd.viol == 0, "o: blocks read = the end / 512, no write");
            $display("o: %0d blocks read", sd.nrd - k8);
        end
        $display("RESULT: %0d/%0d", pass, total);
        if (pass == total) $display("TB PASS");
        else               $display("TB FAIL");
        $finish;
    end
    integer tmo_ms = 900;
    // O9r: instruction trace (+o9rsim): an instruction is done at an edge without stall; PC = its address
    integer tracef = 0, nstep = 0, maxstep = 3000000;
    reg     tron = 1'b0;
    integer dbgfrom = 0;
    initial if ($value$plusargs("steps=%d", maxstep)) ;
    initial if ($value$plusargs("dbg=%d", dbgfrom)) ;
    integer dbgadr = 0;                             // +dbga=<hex>: every load/store at it, the cache line's events
    initial if ($value$plusargs("dbga=%h", dbgadr)) ;
    reg dreq = 1'b0;
    always @(posedge clk) begin
        if (dbgadr != 0 && dut.cache.req_t != dreq && dut.cache.ladr[7:0] == dbgadr[12:5])
            $display("DBC %0d line %h %s", nstep, {dut.cache.ladr, 5'b0}, dut.cache.rw ? "write-back" : "fill");
        dreq <= dut.cache.req_t;
        if (dbgadr != 0 && dut.cache.swr && dut.cache.adr[12:5] == dbgadr[12:5] && tracef != 0)
            $display("DBS %0d store hit adr %h swe %b wdata %h", nstep, dut.cache.adr, dut.cache.swe, dut.cache.wdata);
    end
    always @(posedge clk) if (tracef != 0 && !dut.riscx.stall) begin
        if (dut.riscx.PC == 0) tron = 1'b1;
        if (tron || dut.riscx.PC == 0) begin $fwrite(tracef, "%0X\n", dut.riscx.PC * 4); nstep = nstep + 1; end
        if (dbgadr != 0 && (dut.riscx.LDR | dut.riscx.STR) && ~dut.riscx.stallX && ~dut.riscx.stall1 &&
            dut.riscx.adr == dbgadr)
            $display("DBA %0d PC %h %s %h data %h", nstep, dut.riscx.PC * 4, dut.riscx.STR ? "STR" : "LDR",
                dut.riscx.adr, dut.riscx.STR ? dut.riscx.outbus : dut.riscx.inbus);
        if (dbgfrom > 0 && nstep > dbgfrom && nstep <= dbgfrom + 24)
            $display("DBG %0d PC %h ins %h adr %h inbus %h regmux %h R0 %h R1 %h R2 %h R12 %h R14 %h", nstep,
                dut.riscx.PC * 4, dut.riscx.ins, dut.riscx.adr, dut.riscx.inbus, dut.riscx.regmux, dut.riscx.R[0],
                dut.riscx.R[1], dut.riscx.R[2], dut.riscx.R[12], dut.riscx.R[14]);
    end
    // first X in the CPU's control (PC, IR, stalls): the last PCs before it
    reg [23:0] pch [0:7];
    reg        xseen = 1'b0;
    integer    xk;
    always @(posedge clk) if (rst_n) begin
        for (xk = 7; xk > 0; xk = xk - 1) pch[xk] <= pch[xk - 1];
        pch[0] <= dut.riscx.PC * 4;
        if (!xseen && (^{dut.riscx.PC, dut.riscx.IR, dut.stallX, dut.cwait, dut.codeok, dut.riscx.N, dut.riscx.Z} === 1'bx)) begin
            xseen = 1'b1;
            $display("XDBG %0t: PC %h IR %h ins %h fresh %b PMsel %b stallX %b cwait %b codeok %b rsel %b chit %b cbusy %b adr %h crdata %h",
                $time, dut.riscx.PC * 4, dut.riscx.IR, dut.riscx.ins, dut.riscx.fresh, dut.riscx.PMsel, dut.stallX,
                dut.cwait, dut.codeok, dut.rsel, dut.chit, dut.cbusy, dut.adr, dut.crdata);
            $display("XDBG last PCs: %h %h %h %h %h %h %h %h", pch[0], pch[1], pch[2], pch[3], pch[4], pch[5], pch[6], pch[7]);
        end
    end
    initial begin
        if ($value$plusargs("tmo=%d", tmo_ms)) ;           // +tmo=<ms>: shorter runs while debugging
        #(tmo_ms * 1_000_000.0);
        $display("TIMEOUT");
        $display("state: PC %h IR %h fresh %b PMsel %b stallX %b cwait %b codeok %b rsel %b ldw %b stw %b ws %b",
            dut.riscx.PC * 4, dut.riscx.IR, dut.riscx.fresh, dut.riscx.PMsel, dut.stallX, dut.cwait, dut.codeok,
            dut.rsel, dut.ldw, dut.stw, dut.ws);
        $display("cache: st %0d hit %b r_adr %h tq %h midx %h mtag %h req_t %b a2 %b; psram st %0d ready %b",
            dut.cache.st, dut.chit, dut.cache.r_adr, dut.cache.tq, dut.cache.midx, dut.cache.mtag, dut.cache.req_t,
            dut.cache.a2, dut.psram.st, dut.psram.ready);
        $display("TB FAIL");
        $finish;
    end
endmodule
