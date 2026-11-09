// OBERON_RISC5 port of Wirth's RS232R.v (rtl/wirth/RS232R.v, license rtl/wirth/license.txt).
// Only change: the bit time is a parameter, FAST (fsel=1, 115200) and SLOW (fsel=0, 19200),
// = clock / baud; 217 / 1302 at Wirth's 25 MHz, 234 / 1406 at the Tang's 27 MHz.
`timescale 1ns / 1ps  // NW 4.5.09 / 15.11.10

// RS232 receiver for 19200 or 115200 bps, 8 bit data
// clock is 25 MHz


module RS232R #(parameter FAST = 217, SLOW = 1302) (
    input clk, rst,
	 input RxD,
    input fsel,
    input done,   // "byte has been read"
    output rdy,
    output [7:0] data);

wire endtick, midtick, endbit;
wire [11:0] limit;
reg run, stat;
reg Q0, Q1;  // synchronizer and edge detector
reg [11:0] tick;
reg [3:0] bitcnt;
reg [7:0] shreg;

assign limit = fsel ? FAST : SLOW;  // OBERON_RISC5: was 217 : 1302 (25 MHz)
assign endtick = tick == limit;
assign midtick = tick == {1'b0, limit[11:1]};  // limit/2
assign endbit = bitcnt == 8;
assign data = shreg;
assign rdy = stat;

always @ (posedge clk) begin
  Q0 <= RxD; Q1 <= Q0;
  run <= (Q1 & ~Q0) | ~(~rst | endtick & endbit) & run;
  tick <= (run & ~endtick) ? tick+1 : 0;
  bitcnt <= (endtick & ~endbit) ? bitcnt + 1 :
    (endtick & endbit) ? 0 : bitcnt;
  shreg <= midtick ? {Q1, shreg[7:1]} : shreg;
  stat <= (endtick & endbit) | ~(~rst | done) & stat;
end
endmodule
