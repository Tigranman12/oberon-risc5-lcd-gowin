// OBERON_RISC5 port of Wirth's PROM.v (rtl/wirth/PROM.v, license rtl/wirth/license.txt).
// Changes: the file name is a parameter (Wirth: "../prom.mem"; RISC5.v instantiates "PROM PM" without
// parameters, so the default is the name the build uses: "prom.mem" next to the simulation / synthesis run),
// and $readmemh has an explicit range 0..511.
`timescale 1ns / 1ps // 32-bit PROM initialised from hex file  PDR 23.12.13

module PROM #(parameter FILE = "prom.mem") (input clk,
  input [8:0] adr,
  output reg [31:0] data);

reg [31:0] mem [511: 0];
initial $readmemh(FILE, mem, 0, 511);  // explicit range: mem[511:0] is read from address 0 up
always @(posedge clk) data <= mem[adr];

endmodule
