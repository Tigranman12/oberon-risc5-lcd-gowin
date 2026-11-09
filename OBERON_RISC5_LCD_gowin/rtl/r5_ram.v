`timescale 1ns / 1ps
// r5_ram.v - OBERON_RISC5_FAST (F1, PLAN.md F-D3): the main memory in Tang Nano 9K block RAM, 2^AW words of
// 32 bits, read and written at the RISING edge like Wirth's PROM. RISC5F gives it the next instruction's
// address (pcmux), so rdata after the edge is the current instruction; a load's data comes one clock later
// (r5_tang adds a wait clock through stallX). OBERON_RISC5 used the falling edge (half a cycle).
// Byte writes: RISC5 copies the byte to all four lanes of outbus, the write enable selects the lane.
// Addresses above the RAM wrap (only adr[AW+1:2] is used).
module r5_ram #(parameter AW = 13) (    // 13: 8K words = 32 KB = 16 BSRAM blocks
    input  wire        clk,
    input  wire [23:0] adr,             // byte address from RISC5
    input  wire        wr, ben,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata
);
    reg [7:0] m0 [0:(1<<AW)-1];
    reg [7:0] m1 [0:(1<<AW)-1];
    reg [7:0] m2 [0:(1<<AW)-1];
    reg [7:0] m3 [0:(1<<AW)-1];
    wire [AW-1:0] a = adr[AW+1:2];
    wire [3:0] we = !wr ? 4'b0000 : !ben ? 4'b1111 : (4'b0001 << adr[1:0]);

    always @(posedge clk) begin
        if (we[0]) m0[a] <= wdata[7:0];
        if (we[1]) m1[a] <= wdata[15:8];
        if (we[2]) m2[a] <= wdata[23:16];
        if (we[3]) m3[a] <= wdata[31:24];
        rdata <= {m3[a], m2[a], m1[a], m0[a]};
    end
endmodule
