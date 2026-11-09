`timescale 1ns / 1ps
// rpll_stub.v - a stand-in for Gowin's rPLL, only so that iverilog can compile rtl/r5_board.v in the regression
// (tests/run_all.sh SYNTAX). Same ports as Gowin's primitive; CLKOUT = CLKIN / 2, LOCK = 1. Not a PLL model.
module rPLL #(
    parameter FCLKIN = "100.0", DEVICE = "GW1N-4",
    parameter IDIV_SEL = 0, FBDIV_SEL = 0, ODIV_SEL = 8,
    parameter DYN_IDIV_SEL = "false", DYN_FBDIV_SEL = "false", DYN_ODIV_SEL = "false",
    parameter CLKFB_SEL = "internal", CLKOUT_BYPASS = "false", CLKOUTP_BYPASS = "false", CLKOUTD_BYPASS = "false",
    parameter DYN_DA_EN = "false", DYN_SDIV_SEL = 2, CLKOUTD_SRC = "CLKOUT", CLKOUTD3_SRC = "CLKOUT"
) (
    input  CLKIN, CLKFB, RESET, RESET_P,
    input  [5:0] FBDSEL, IDSEL, ODSEL,
    input  [3:0] PSDA, DUTYDA, FDLY,
    output reg CLKOUT = 1'b0,
    output LOCK, CLKOUTP, CLKOUTD, CLKOUTD3
);
    always @(posedge CLKIN) CLKOUT <= ~CLKOUT;
    assign LOCK = 1'b1;
    assign CLKOUTP = CLKOUT, CLKOUTD = CLKOUT, CLKOUTD3 = CLKOUT;
endmodule
