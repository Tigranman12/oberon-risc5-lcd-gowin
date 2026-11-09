`timescale 1ns / 1ps
// tb_lcd.v - OBERON_RISC5_LCD_gowin L1: rtl/r5_lcd.v alone (run_lcd.sh, a few seconds).
//   1. The CPU port writes all 4080 words (a pseudo-random picture), then byte-lane writes into some words;
//      a shadow copy follows every write.
//   2. Every word is read back through the CPU port (rdata one clock after the address) = the shadow.
//   3. One whole panel frame is recorded at the falling edges of lcd_clk (data is stable there):
//      272 lines of exactly 480 pixels with lcd_de, colours only white (FFFFH) or black, and every pixel =
//      bit x MOD 32 of shadow word y * 15 + x DIV 32 (Display.Mod's layout), with ROT = 1 (default): y = line,
//      x = 479 - position; ROT = 0: y = 271 - line, x = position (run_lcd.sh runs both);
//      lcd_clk periods per frame = 560 x 297, one hsync and one vsync pulse per line / frame.
//   The frame is also written to lcd_frame.pbm (P1, 480 x 272) for a look.
// Last lines: "RESULT: n/m" and "TB PASS" or "TB FAIL".
module tb_lcd;
    reg clk = 1'b0, lclk = 1'b0;
    always #29.63 clk  = ~clk;           // 16.875 MHz, the CPU clock
    always #18.52 lclk = ~lclk;          // 27 MHz
    reg         we = 1'b0;
    reg  [3:0]  be = 4'h0;
    reg  [11:0] a = 12'd0;
    reg  [31:0] wdata = 32'd0;
    wire [31:0] rdata;
    wire        lcd_clk, lcd_de, lcd_hsync, lcd_vsync;
    wire [4:0]  lcd_r, lcd_b;
    wire [5:0]  lcd_g;
    r5_lcd #(.ROT180(ROT)) dut (.clk(clk), .we(we), .be(be), .a(a), .wdata(wdata), .rdata(rdata), .lclk(lclk),
        .lcd_clk(lcd_clk), .lcd_de(lcd_de), .lcd_hsync(lcd_hsync), .lcd_vsync(lcd_vsync),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b));

    reg [31:0] sh [0:4095];
    integer pass = 0, total = 0;
    task check(input ok, input [8*60-1:0] what);
        begin
            total = total + 1;
            if (ok) begin pass = pass + 1; $display("PASS: %0s", what); end
            else $display("FAIL: %0s", what);
        end
    endtask
    task wr(input [11:0] wa, input [3:0] wbe, input [31:0] d);
        begin
            @(negedge clk); a = wa; be = wbe; wdata = d; we = 1'b1;
            @(negedge clk); we = 1'b0;
            if (wbe[0]) sh[wa][7:0]   = d[7:0];
            if (wbe[1]) sh[wa][15:8]  = d[15:8];
            if (wbe[2]) sh[wa][23:16] = d[23:16];
            if (wbe[3]) sh[wa][31:24] = d[31:24];
        end
    endtask

    // frame recorder
    integer x = 0, line = 0, nlines = 0, badlen = 0, badpix = 0, badcol = 0, nclk = 0, nhs = 0, nvs = 0;
    integer recording = 0, done = 0, fd, y, w, i, rbad, xo;
    parameter ROT = 1;                               // = r5_lcd's ROT180
    reg     de_d = 1'b0, hs_d = 1'b0, vs_d = 1'b0, pix, expv;
    always @(negedge lcd_clk) begin
        if (recording) begin
            nclk = nclk + 1;
            if (lcd_hsync & ~hs_d) nhs = nhs + 1;
            if (lcd_de) begin
                pix = ({lcd_r, lcd_g, lcd_b} == 16'hFFFF);
                if ({lcd_r, lcd_g, lcd_b} != 16'hFFFF && {lcd_r, lcd_g, lcd_b} != 16'h0000) badcol = badcol + 1;
                y  = ROT ? line : 271 - line;        // ROT180 (default): line l = y l, position p = x 479 - p
                xo = ROT ? 479 - x : x;
                w = sh[y * 15 + xo / 32];
                expv = w[xo % 32];
                if (pix !== expv) begin
                    if (badpix < 5) $display("  pixel x %0d line %0d: %b, expected %b", x, line, pix, expv);
                    badpix = badpix + 1;
                end
                if (line < 272) $fwrite(fd, "%0d%s", pix, (x % 40 == 39) ? "\n" : " ");
                x = x + 1;
            end
            if (~lcd_de & de_d) begin                // end of an active line
                if (x != 480) badlen = badlen + 1;
                x = 0; line = line + 1; nlines = nlines + 1;
            end
        end
        if (lcd_vsync & ~vs_d) begin                 // a vsync pulse: start / stop recording
            nvs = nvs + 1;
            if (recording) begin recording = 0; done = 1; end
            else if (!done && nvs == 1) begin recording = 1; nclk = 0; nhs = 0; line = 0; x = 0; end
        end
        de_d = lcd_de; hs_d = lcd_hsync; vs_d = lcd_vsync;
    end

    initial begin
        for (i = 0; i < 4096; i = i + 1) sh[i] = 32'hx;
        // 1. the picture: all 4080 words, then byte lanes
        for (i = 0; i < 4080; i = i + 1) wr(i, 4'hF, (i * 32'h9E3779B1) ^ (i << 7) ^ 32'h5A5A0F0F);
        wr(0, 4'hF, 32'hFFFFFFFF);                   // bottom line, x 0..31: white
        wr(4065, 4'hF, 32'h00000001);                // top line (y = 271): only x = 0
        wr(100, 4'b0001, 32'h000000AB);
        wr(101, 4'b0010, 32'h0000CD00);
        wr(102, 4'b0100, 32'h00EF0000);
        wr(103, 4'b1000, 32'h12000000);
        // 2. read back
        rbad = 0;
        for (i = 0; i < 4080; i = i + 1) begin
            @(negedge clk); a = i;
            @(negedge clk);                          // rdata was taken at the edge in between
            if (rdata !== sh[i]) begin
                if (rbad < 5) $display("  word %0d: %h, expected %h", i, rdata, sh[i]);
                rbad = rbad + 1;
            end
        end
        check(rbad == 0, "CPU port: 4080 words read back (word writes)");
        check(sh[100][7:0] == 8'hAB && sh[101][15:8] == 8'hCD && sh[102][23:16] == 8'hEF && sh[103][31:24] == 8'h12
              && rbad == 0, "CPU port: byte lanes 0-3 written alone");
        // 3. one frame
        fd = $fopen("lcd_frame.pbm", "w");
        $fwrite(fd, "P1\n480 272\n");
        wait (done == 1);
        $fclose(fd);
        check(nlines == 272 && badlen == 0, "LCD: 272 lines of 480 pixels (lcd_de)");
        check(badcol == 0, "LCD: colours only white / black");
        check(badpix == 0, "LCD: every pixel = Display.Mod's bit (ROT180 or not)");
        check(nclk == 560 * 297, "LCD: 560 x 297 pixel clocks per frame");
        check(nhs == 297, "LCD: 297 hsync pulses per frame");
        $display("frame: %0d lines, %0d pixel clocks, %0d hsync, bad: len %0d pix %0d col %0d",
                 nlines, nclk, nhs, badlen, badpix, badcol);
        $display("RESULT: %0d/%0d", pass, total);
        if (pass == total) $display("TB PASS"); else $display("TB FAIL");
        $finish;
    end
    initial begin #60_000_000; $display("TIMEOUT"); $display("TB FAIL"); $finish; end
endmodule
