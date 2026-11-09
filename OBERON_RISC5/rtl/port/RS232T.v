// OBERON_RISC5 port of Wirth's RS232T.v (rtl/wirth/RS232T.v, license rtl/wirth/license.txt).
// Only change: the bit time is a parameter, FAST (fsel=1, 115200) and SLOW (fsel=0, 19200),
// = clock / baud; 217 / 1302 at Wirth's 25 MHz, 234 / 1406 at the Tang's 27 MHz.
`timescale 1ns / 1ps  // NW 4.5.09 / 15.8.10 / 15.11.10

// RS232 transmitter for 19200 bps, 8 bit data
// clock is 25 MHz; 25000 / 1302 = 19.2 KHz

module RS232T #(parameter FAST = 217, SLOW = 1302) (
    input clk, rst,
    input start, // request to accept and send a byte
	 input fsel,  // frequency selection
    input [7:0] data,
    output rdy,
    output TxD);

wire endtick, endbit;
wire [11:0] limit;
reg run;
reg [11:0] tick;
reg [3:0] bitcnt;
reg [8:0] shreg;

assign limit = fsel ? FAST : SLOW;  // OBERON_RISC5: was 217 : 1302 (25 MHz)
assign endtick = tick == limit;
assign endbit = bitcnt == 9;
assign rdy = ~run;
assign TxD = shreg[0];

always @ (posedge clk) begin
  run <= (~rst | endtick & endbit) ? 0 : start ? 1 : run;
  tick <= (run & ~endtick) ? tick + 1 : 0;
  bitcnt <= (endtick & ~endbit) ? bitcnt + 1 :
    (endtick & endbit) ? 0 : bitcnt;
  shreg <= (~rst) ? 1 : start ? {data, 1'b0} :
    endtick ? {1'b1, shreg[8:1]} : shreg;
end
endmodule
