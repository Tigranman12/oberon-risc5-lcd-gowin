`timescale 1ns / 1ps
// r5_tang.v - OBERON_RISC5_FAST (copy of OBERON_RISC5's, F1): Wirth's RISC5 on the Tang Nano 9K.
// Replaces Wirth's RISC5Top.v (Xilinx Spartan board with external SRAM, VGA, PS/2): same I/O map,
// CPU = RISC5F.v (RISC5.v with rising-edge RAM, PLAN.md F-D3), its units unchanged (../OBERON_RISC5/rtl/wirth),
// memory in block RAM (r5_ram.v; O6: the PSRAM through r5_cache), terminal = the TTY. F1: one wait clock per load.
//
//   clk     27 MHz crystal (pin 52), used directly: CLK_HZ sets the UART bit times and the ms timer
//   rst_n   S1 (pin 4): restart; a power-on reset also runs after the bitstream loads
//   SWI     Wirth's switches (S1: a parameter; S3 puts switch 0 on the S2 button: BootLoad 1 = serial line)
//   uart    pins 18 (RX) / 17 (TX): the on-board USB serial port (BL702), PuTTY on the PC
//   led     6 LEDs, active low: Wirth's LED register bit 7 on led[5], bits 4..0 on led[4:0]
//   mclk, mrst  O3: the PSRAM controller's clock (54 MHz, own PLL) and reset; psram_*: channel 0 pins
//   sd_*    O4 (PLAN.md F-D10): the microSD slot in SPI mode (pins 36 SCLK, 37 MOSI, 38 CS, 39 MISO), Wirth's
//           SPI.v: control bit 0 selects the card (CS low), bit 2 = fast (clk/3, words), else slow (clk/64, bytes)
//   O3 (PLAN.md F-D9): 400000H-7FFFFFH = PSRAM channel 0 (4 MB, r5_psram); I/O word 8 (FFFFE0H) = its status.
//   O5 (F-D11): through r5_cache (8 KB): code runs from there too; I/O words 9, 10 = cache misses, write-backs.
//   O6 (F-D12): memory map as Wirth's: 000000H-3FFFFFH = the PSRAM (4 MB) through an 8 KB cache; boot ROM
//   FFE000H; I/O FFFFC0H. No block RAM main memory any more.
//   lcd_*   OBERON_RISC5_LCD_gowin L1: 400000H-403FFFH = the LCD frame memory (r5_lcd, 480 x 272 x 1 bit);
//           lclk = the 27 MHz crystal for its LCD side.
//
// I/O addresses (Wirth's RISC5Top.v), word n at -64 + 4n (FFFFC0H + 4n):
//   0 ms counter / --         1 switches, buttons / LEDs     2 RS-232 data / data (starts sending)
//   3 RS-232 status {rdyTx, rdyRx} / control (bit 0: 1 = 115200, 0 = 19200)
//   4 SPI data / data (start)  5 SPI status / control {fast, -, net, SD card} (O4: the SD card)
//   6, 7 mouse, keyboard: 0 (no PS/2 on this board)
module r5_tang #(parameter CLK_HZ = 27_000_000, parameter [7:0] SWI = 8'h00) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [5:0] led,
    input  wire       mclk, mrst,
    output wire       psram_ck, psram_cs_n, psram_reset_n,
    inout  wire [7:0] psram_dq,
    inout  wire       psram_rwds,
    output wire       sd_sclk, sd_mosi, sd_cs_n,     // O4
    input  wire       sd_miso,
    input  wire       lclk,                          // L1: 27 MHz for the LCD side of r5_lcd
    output wire       lcd_clk, lcd_de, lcd_hsync, lcd_vsync,
    output wire [4:0] lcd_r,
    output wire [5:0] lcd_g,
    output wire [4:0] lcd_b
);
    localparam FAST = CLK_HZ / 115200;  // 234 at 27 MHz
    localparam SLOW = CLK_HZ / 19200;   // 1406
    localparam MS   = CLK_HZ / 1000 - 1;

    // reset: power-on (15 clocks) and the S1 button, synchronised. RISC5's rst is active LOW.
    reg [3:0] por = 4'd0;
    reg b1 = 1'b0, b2 = 1'b0, rst = 1'b0;
    always @(posedge clk) begin
        b1 <= rst_n;
        b2 <= b1;
        if (por != 4'hF) por <= por + 4'd1;
        rst <= (por == 4'hF) && b2;
    end

    wire [23:0] adr;
    wire [3:0]  iowadr = adr[5:2];
    wire [31:0] inbus, outbus;
    wire        rd, wr, ben;
    wire        ioenb = (adr[23:6] == 18'h3FFFF);

    wire [7:0]  dataRx;
    wire        rdyRx, rdyTx;
    wire [31:0] spiRx;
    wire        spiRdy;
    reg  [7:0]  Lreg = 8'd0;
    reg  [15:0] cnt0 = 16'd0;
    reg  [31:0] cnt1 = 32'd0;           // milliseconds
    reg  [3:0]  spiCtrl = 4'd0;
    reg         bitrate = 1'b0;
    wire        limit = (cnt0 == MS);

    // F1: one wait clock per load (PLAN.md F-D3): stallX in the load's first clock, while the RAM reads.
    // O5: ws = "the RAM / cache read at the last edge was this load's or store's address" (a fetch-miss stall
    // before the load also holds stallX, so ws is not simply the last stallX).
    wire ldw, stw, bw, stallX, cwait;
    reg  ws = 1'b0;
    always @(posedge clk) ws <= (ldw | stw) & stallX;

    // O5 (PLAN.md F-D11): the PSRAM through r5_cache (code, loads, stores); O6 (F-D12): at 000000H-3FFFFFH, the
    // block RAM main memory is gone (its 16 BSRAM are the 32 KB cache).
    //   Fetch: rsel = the address read at the last edge was in the PSRAM; codeok = the cache had it.
    //   Load / store: first clock (ws = 0) the cache reads; second clock: hit -> done (a store writes its lanes
    //   into the cache), miss -> the cache fills (and writes back) while stallX stays high, then hits.
    wire        psel = (adr[23:22] == 2'b00);          // O6: 0-3FFFFFH (O5: 400000H-7FFFFFH)
    wire        dacc = (ldw | stw) & psel;
    reg         rsel = 1'b0;
    always @(posedge clk) rsel <= psel;
    wire [31:0] crdata, nmiss, nwb, pstatus;
    wire        chit, cbusy, preq_t, prw, pack_t;
    wire [16:0] pladr;
    wire [255:0] pwline, prline;
    wire        codeok = ~rsel | (chit & ~cbusy);
    assign stallX = dacc ? (~ws | ~chit | cbusy) : (ldw & ~ws);
    r5_cache #(.IW(8)) cache (.clk(clk), .adr(adr), .cwait(cwait), .dmiss_req(dacc & ws), .swr(wr & psel),
        .swe(ben ? (4'b0001 << adr[1:0]) : 4'b1111), .wdata(outbus), .rdata(crdata), .hit(chit), .busy(cbusy),
        .nmiss(nmiss), .nwb(nwb), .req_t(preq_t), .rw(prw), .ladr(pladr), .wline(pwline), .ack_t(pack_t),
        .rline(prline));
    r5_psram psram (.clk(mclk), .rst(mrst), .req_t(preq_t), .rw(prw), .ladr(pladr), .wline(pwline),
        .ack_t(pack_t), .rline(prline), .status(pstatus),
        .ck(psram_ck), .cs_n(psram_cs_n), .reset_n(psram_reset_n), .dq(psram_dq), .rwds(psram_rwds));

    RISC5F riscx (.clk(clk), .rst(rst), .rd(rd), .wr(wr), .ben(ben), .stallX(stallX), .ldw(ldw), .stw(stw), .bw(bw),
        .adr(adr), .codebus(crdata), .inbus(inbus), .outbus(outbus), .codeok(codeok), .cwait(cwait));

    RS232R #(.FAST(FAST), .SLOW(SLOW)) receiver (.clk(clk), .rst(rst), .RxD(uart_rx), .fsel(bitrate),
        .done(rd & ioenb & (iowadr == 2)), .data(dataRx), .rdy(rdyRx));
    RS232T #(.FAST(FAST), .SLOW(SLOW)) transmitter (.clk(clk), .rst(rst),
        .start(wr & ioenb & (iowadr == 2)), .fsel(bitrate), .data(outbus[7:0]), .TxD(uart_tx), .rdy(rdyTx));
    SPI spi (.clk(clk), .rst(rst), .start(wr & ioenb & (iowadr == 4)), .dataTx(outbus),
        .fast(spiCtrl[2]), .dataRx(spiRx), .rdy(spiRdy), .SCLK(sd_sclk), .MOSI(sd_mosi), .MISO(sd_miso));   // O4
    assign sd_cs_n = ~spiCtrl[0];                       // Wirth: SS = ~spiCtrl[1:0] (O4)

    // L1 (PLAN.md L-D2, L-D3): the LCD frame memory at 400000H-403FFFH, outside the PSRAM (psel = 0), so a load
    // takes the one wait clock of stallX = ldw & ~ws, while r5_lcd reads; a store writes in its own clock.
    wire        fsel = (adr[23:14] == 10'h100);
    wire [31:0] fdata;
    r5_lcd lcd (.clk(clk), .we(wr & fsel), .be(ben ? (4'b0001 << adr[1:0]) : 4'b1111), .a(adr[13:2]),
        .wdata(outbus), .rdata(fdata), .lclk(lclk), .lcd_clk(lcd_clk), .lcd_de(lcd_de), .lcd_hsync(lcd_hsync),
        .lcd_vsync(lcd_vsync), .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b));

    assign inbus = ~ioenb ? (fsel ? fdata : crdata) :   // O6: all other memory is the PSRAM
        ((iowadr == 0) ? cnt1 :
         (iowadr == 1) ? {20'b0, 4'b0, SWI} :
         (iowadr == 2) ? {24'b0, dataRx} :
         (iowadr == 3) ? {30'b0, rdyTx, rdyRx} :
         (iowadr == 4) ? spiRx :
         (iowadr == 5) ? {31'b0, spiRdy} :
         (iowadr == 8) ? pstatus :                     // O3
         (iowadr == 9) ? nmiss : (iowadr == 10) ? nwb : 32'b0);   // O5: cache misses, write-backs

    always @(posedge clk) begin
        Lreg    <= ~rst ? 8'd0 : (wr & ioenb & (iowadr == 1)) ? outbus[7:0] : Lreg;
        cnt0    <= limit ? 16'd0 : cnt0 + 16'd1;
        cnt1    <= cnt1 + limit;
        spiCtrl <= ~rst ? 4'd0 : (wr & ioenb & (iowadr == 5)) ? outbus[3:0] : spiCtrl;
        bitrate <= ~rst ? 1'b0 : (wr & ioenb & (iowadr == 3)) ? outbus[0] : bitrate;
    end
    assign led = ~{Lreg[7], Lreg[4:0]};
endmodule
