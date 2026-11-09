`timescale 1ns / 1ps
// r5_board.v - the Gowin top of OBERON_RISC5 (PLAN.md D4): Gowin's rPLL makes 16.875 MHz from the 27 MHz crystal,
// and r5_tang runs on it. OBERON_RISC5_FAST F2: RISC5F reaches Fmax 19.6 MHz (logs/20261103-170603-rf_gowin;
// the next path, RAM -> ALU -> register file, is 20.1 MHz); 16.875 MHz keeps 16 % margin (PLAN.md F-D6). Why 13.5: the first build at 27 MHz reached only 18.2 MHz
// (logs/20261103-125327-r5_gowin): the boot-ROM instruction -> store decode -> RAM write enable path must
// fit half a cycle (falling-edge RAM, D3) and needs 27.7 ns; at 13.5 MHz half a cycle is 37 ns.
// rPLL: CLKOUT = 27 / (IDIV_SEL+1) * (FBDIV_SEL+1) = 27 / 8 * 5 = 16.875 MHz (phase detector 3.375 MHz >= 3);
// VCO = 16.875 * ODIV_SEL (64) = 1080 MHz (range 400..1200).
// The CPU stays in reset until the PLL has locked. Simulation tests r5_tang directly (tb/tb_r5.v).
// O3 (PLAN.md F-D9): a second rPLL makes 54 MHz (27 x 2; VCO 432) for the PSRAM controller (r5_psram in
// r5_tang); the CPU clock is unchanged. The PSRAM ports carry GowinSynthesis' fixed names for the GW1NR-9's
// in-package HyperRAM (2 channels of 8 bits; no pins in r5.cst): channel 0 is used, channel 1 stays idle.
// OBERON_RISC5_LCD_gowin L1: the LCD pins; the LCD side of r5_lcd runs on the 27 MHz crystal itself.
module r5_board (
    input  wire       clk,       // 27 MHz, pin 52
    input  wire       rst_n,     // S1
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [5:0] led,
    output wire       sd_sclk, sd_mosi, sd_cs_n,     // O4: microSD slot (SPI mode)
    input  wire       sd_miso,
    output wire [1:0]  O_psram_ck, O_psram_ck_n, O_psram_cs_n, O_psram_reset_n,
    inout  wire [1:0]  IO_psram_rwds,
    inout  wire [15:0] IO_psram_dq,
    output wire       lcd_clk, lcd_de, lcd_hsync, lcd_vsync,   // L1: the 4.3" LCD (pins as G9_FTL_ARCH_V3)
    output wire [4:0] lcd_r,
    output wire [5:0] lcd_g,
    output wire [4:0] lcd_b
);
    wire clk_cpu, lock;
    rPLL #(
        .FCLKIN("27"), .DEVICE("GW1NR-9C"),
        .IDIV_SEL(7), .FBDIV_SEL(4), .ODIV_SEL(64),
        .DYN_IDIV_SEL("false"), .DYN_FBDIV_SEL("false"), .DYN_ODIV_SEL("false"),
        .CLKFB_SEL("internal"), .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
        .DYN_DA_EN("false"), .DYN_SDIV_SEL(2), .CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT")
    ) pll (
        .CLKIN(clk), .CLKFB(1'b0), .RESET(1'b0), .RESET_P(1'b0),
        .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0),
        .CLKOUT(clk_cpu), .LOCK(lock), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3()
    );

    // ---- O3: the PSRAM controller's clock ----
    wire mclk, mlock;
    rPLL #(
        .FCLKIN("27"), .DEVICE("GW1NR-9C"),
        .IDIV_SEL(0), .FBDIV_SEL(1), .ODIV_SEL(8),   // 54 MHz: at 67.5 the controller reached 62.3 (logs/20261103-204824-rf_gowin)
        .DYN_IDIV_SEL("false"), .DYN_FBDIV_SEL("false"), .DYN_ODIV_SEL("false"),
        .CLKFB_SEL("internal"), .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
        .DYN_DA_EN("false"), .DYN_SDIV_SEL(2), .CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT")
    ) mpll (
        .CLKIN(clk), .CLKFB(1'b0), .RESET(1'b0), .RESET_P(1'b0),
        .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0),
        .CLKOUT(mclk), .LOCK(mlock), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3()
    );
    reg m1 = 1'b0, m2 = 1'b0;                  // controller reset until its PLL has locked
    always @(posedge mclk) begin m1 <= mlock; m2 <= m1; end

    wire ck0;
    assign O_psram_ck      = {1'b0, ck0};
    assign O_psram_ck_n    = {1'b1, ~ck0};
    assign O_psram_cs_n[1] = 1'b1;
    assign O_psram_reset_n[1] = 1'b1;
    assign IO_psram_rwds[1] = 1'bz;
    assign IO_psram_dq[15:8] = 8'hzz;

    r5_tang #(.CLK_HZ(16_875_000)) core (.clk(clk_cpu), .rst_n(rst_n & lock),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .led(led),
        .mclk(mclk), .mrst(~m2),
        .psram_ck(ck0), .psram_cs_n(O_psram_cs_n[0]), .psram_reset_n(O_psram_reset_n[0]),
        .psram_dq(IO_psram_dq[7:0]), .psram_rwds(IO_psram_rwds[0]),
        .sd_sclk(sd_sclk), .sd_mosi(sd_mosi), .sd_cs_n(sd_cs_n), .sd_miso(sd_miso),
        .lclk(clk), .lcd_clk(lcd_clk), .lcd_de(lcd_de), .lcd_hsync(lcd_hsync), .lcd_vsync(lcd_vsync),
        .lcd_r(lcd_r), .lcd_g(lcd_g), .lcd_b(lcd_b));     // L1: the LCD side runs on the 27 MHz crystal
endmodule
