`timescale 1ns / 1ps
// sd_spi_model.v - OBERON_RISC5_FAST O4: a behavioural SDHC card in SPI mode (mode 0: the card takes MOSI at the
// rising SCLK edge and changes MISO TCO ns after the falling one; MISO = 1 while CS is high), for tb_mon.
//   Commands (48 bits: 01 cccccc, arg, crc): CMD0 (crc 95H checked) -> R1 01; CMD8 (arg 1AAH, crc 87H checked)
//   -> R7 01 000001AA; CMD55 -> R1; ACMD41 with HCS -> 01 for ACMD41_BUSY tries, then 00 (ready); CMD58 -> R1 + OCR
//   (C0FF8000: powered up, CCS = 1 = block addresses); CMD16 -> R1; CMD17 (block address) -> R1 00, a few FF, the
//   token FE, 512 bytes, 2 CRC bytes. Each response comes one byte after the command (NCR = 1). Others -> R1 04.
//   Sector s, byte i = s * 31 + i * 7 + 3 (mod 256), except bytes 510, 511 of sector 0 = 55H, AAH (an MBR).
//   O8: with +sdimg the blocks IMGBASE.. hold build/core_img.hex (tools/mkcore.py: a test inner core).
// Checks (counted in viol, printed): fewer than 74 clocks with CS high before CMD0, a command before CMD0, any
// write or erase command (CMD24, 25, 27, 32, 33, 38, 42, ACMD23): the O4 programs must only read the card.
// O7: with +sdwrite, CMD24 to blocks WBASE..WBASE+WN-1 is allowed (others still count as violations): start token
// FEH, 512 bytes, 2 CRC bytes -> data response 05H, 3 busy bytes 00H; CMD17 then reads what was written (nwr counts).
// +sdsc: a standard-capacity card: CMD58's CCS = 0, CMD17 / CMD24 take byte addresses (must be 512-aligned).
module sd_spi_model #(parameter ACMD41_BUSY = 2, parameter TCO = 5.0) (
    input  wire sclk, mosi, cs_n,
    output reg  miso = 1'b1
);
    integer viol = 0, nrd = 0, pre = 0;
    reg       inited = 1'b0, ready = 1'b0, app = 1'b0;
    integer   a41 = 0;
    reg [7:0] ib = 8'd0;                        // byte coming in
    integer   bc = 0;                           // bits of it
    reg [7:0] cmdb [0:5];
    integer   cn = 0;                           // command bytes taken (0 = waiting for a start byte)
    reg [7:0] q [0:1023];                       // bytes to send
    integer   qh = 0, qt = 0;
    reg [7:0] ob = 8'hFF;                       // byte going out
    integer   i;
    localparam WBASE = 32'h80010, WN = 4;
    reg [7:0] wmem [0:WN*512-1];
    reg [3:0] wvalid = 4'd0;
    integer   nwr = 0, wst = 0, wk = 0;
    reg [31:0] wblk = 0;

    localparam IMGBASE = 32'h80004, IMGMAX = 8192;
    reg [7:0] img [0:IMGMAX-1];
    integer   imgn = 0;
    initial if ($test$plusargs("sdimg")) begin
        for (i = 0; i < IMGMAX; i = i + 1) img[i] = 8'hxx;
        $readmemh("core_img.hex", img);
        imgn = 0;
        while (imgn < IMGMAX && img[imgn] !== 8'hxx) imgn = imgn + 1;
        $display("SDCARD: image of %0d bytes at block %h", imgn, IMGBASE);
    end
    function [7:0] ib8(input [31:0] s, input integer k);   // the byte served: written, the image, or the pattern
        ib8 = (s >= WBASE && s < WBASE + WN && wvalid[s - WBASE]) ? wmem[(s - WBASE) * 512 + k] :
              (imgn > 0 && s >= IMGBASE && (s - IMGBASE) * 512 + k < imgn) ? img[(s - IMGBASE) * 512 + k] :
              (imgn > 0 && s >= IMGBASE && s < IMGBASE + 64) ? 8'h00 : sb(s, k);
    endfunction
    task put(input [7:0] x); begin q[qt % 1024] = x; qt = qt + 1; end endtask
    function [7:0] sb(input integer s, input integer k);
        sb = (s == 0 && k == 510) ? 8'h55 : (s == 0 && k == 511) ? 8'hAA : (s * 31 + k * 7 + 3);
    endfunction

    task command;
        reg [5:0]  c;
        reg [31:0] a;
        reg [7:0]  crc;
        begin
            c = cmdb[0][5:0]; a = {cmdb[1], cmdb[2], cmdb[3], cmdb[4]}; crc = cmdb[5];
            if ($test$plusargs("sdsc") && (c == 17 || c == 24)) begin
                if (a[8:0] != 0) begin viol = viol + 1; $display("SDCARD: SDSC address %h not 512-aligned", a); end
                a = a >> 9;
            end
            if ($test$plusargs("sddbg")) $display("SDCARD: CMD%0d %h", c, a);
            put(8'hFF);                                                   // NCR
            if (!inited && c != 0) begin viol = viol + 1; $display("SDCARD: CMD%0d before CMD0", c); end
            if (app && c == 23) begin viol = viol + 1; $display("SDCARD: ACMD23 (write)"); end
            if (!app && c == 24 && ready && $test$plusargs("sdwrite") && a >= WBASE && a < WBASE + WN) begin
                wst = 1; wblk = a; put(8'h00);
            end else if (!app && (c == 24 || c == 25 || c == 27 || c == 32 || c == 33 || c == 38 || c == 42)) begin
                viol = viol + 1; $display("SDCARD: write/erase command CMD%0d arg %h", c, a);
            end
            if (c == 0) begin
                if (pre < 74) begin viol = viol + 1; $display("SDCARD: %0d clocks before CMD0 (< 74)", pre); end
                if (crc != 8'h95) begin viol = viol + 1; $display("SDCARD: CMD0 crc %h", crc); end
                inited = 1'b1; ready = 1'b0; a41 = 0; put(8'h01);
            end else if (c == 8) begin
                if (crc != 8'h87 || a != 32'h1AA) begin viol = viol + 1; $display("SDCARD: CMD8 %h crc %h", a, crc); end
                put(8'h01); put(8'h00); put(8'h00); put(8'h01); put(8'hAA);
            end else if (c == 55) put(ready ? 8'h00 : 8'h01);
            else if (app && c == 41) begin
                a41 = a41 + 1;
                if (a41 > ACMD41_BUSY && a[30]) ready = 1'b1;
                put(ready ? 8'h00 : 8'h01);
            end else if (c == 58) begin
                put(ready ? 8'h00 : 8'h01);
                put(ready ? ($test$plusargs("sdsc") ? 8'h80 : 8'hC0) : 8'h00); put(8'hFF); put(8'h80); put(8'h00);
            end else if (c == 24 && wst == 1) ;                           // answered above
            else if (c == 16) put(ready ? 8'h00 : 8'h01);
            else if (c == 17 && ready) begin
                put(8'h00); put(8'hFF); put(8'hFF); put(8'hFF); put(8'hFE);
                for (i = 0; i < 512; i = i + 1) put(ib8(a, i));
                put(8'h12); put(8'h34);
                nrd = nrd + 1;
            end else put(8'h04);                                          // illegal command
            app = (c == 55);
        end
    endtask

    always @(posedge sclk) begin
        if (cs_n) pre = pre + 1;
        else begin
            ib = {ib[6:0], mosi}; bc = bc + 1;
            if (bc == 8) begin
                bc = 0;
                if (wst == 1) begin                                     // O7: a block coming
                    if (ib == 8'hFE) begin wst = 2; wk = 0; end
                end else if (wst == 2) begin
                    wmem[(wblk - WBASE) * 512 + wk] = ib; wk = wk + 1;
                    if (wk == 512) begin wst = 3; wk = 0; end
                end else if (wst == 3) begin
                    wk = wk + 1;
                    if (wk == 2) begin
                        wst = 0; wvalid[wblk - WBASE] = 1'b1; nwr = nwr + 1;
                        put(8'h05); put(8'h00); put(8'h00); put(8'h00);
                    end
                end else if (cn == 0) begin
                    if (ib[7:6] == 2'b01) begin cmdb[0] = ib; cn = 1; end
                end else begin
                    cmdb[cn] = ib; cn = cn + 1;
                    if (cn == 6) begin cn = 0; command; end
                end
            end
        end
    end
    // MISO: the next byte's first bit after the falling edge that ends a byte, else the next bit
    always @(negedge sclk) if (!cs_n) begin
        if (bc == 0) begin
            if (qh != qt) begin ob = q[qh % 1024]; qh = qh + 1; end else ob = 8'hFF;
        end else ob = {ob[6:0], 1'b1};
        miso <= #(TCO) ob[7];
    end
    always @(cs_n) begin
        bc = 0; cn = 0; ob = 8'hFF;
        miso <= #(TCO) 1'b1;
    end
endmodule
