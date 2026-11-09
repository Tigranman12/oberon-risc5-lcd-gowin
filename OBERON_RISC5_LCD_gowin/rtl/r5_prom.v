`timescale 1ns / 1ps
// r5_prom.v - OBERON_RISC5_FAST O8: the boot ROM, 1024 words (Wirth's PROM.v has 512; OBERON_RISC5's port of it
// stays unchanged). FFE000H-FFEFFFH; RISC5F reads it at the rising edge with the next address (pcmux[9:0]).
// 2 BSRAM. Holds the monitor (programs/monitor.s) with its O8 command 'o' (Wirth's BootLoad.LoadFromDisk).
module r5_prom #(parameter FILE = "prom.mem") (input clk, input [9:0] adr, output reg [31:0] data);
    reg [31:0] mem [0:1023];
    initial $readmemh(FILE, mem, 0, 1023);
    always @(posedge clk) data <= mem[adr];
endmodule
