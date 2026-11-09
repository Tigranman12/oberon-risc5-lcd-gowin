`timescale 1ns / 1ps  // 25.9.2015
// RISC5F.v - OBERON_RISC5_FAST stage F1: Wirth's RISC5.v (../OBERON_RISC5/rtl/wirth/RISC5.v, 25.9.2015,
// license ../OBERON_RISC5/rtl/wirth/license.txt) changed for block RAM read at the RISING edge (PLAN.md F-D3).
// Every change is marked "F1:". Wirth's memory answers in the same clock (asynchronous SRAM); here the RAM,
// like Wirth's own PROM, is read at the rising edge with the next address (pcmux), so its output (codebus)
// IS the current instruction after a normal clock. After a stall it is not (a load's data, or a re-read),
// so IR keeps the instruction and `fresh` says which one to decode.
// Loads: the outside (r5_tang) holds stallX high for the first clock of each load (`ldw`); the RAM reads the
// data at its end, and Wirth's unchanged logic takes it in the next clock (address, byte select, rd, regwr).
// F2: the multi-clock units (MUL, DIV, FAD/FSB, FML, FDV) get their operands from registers (opB, opC0, opC1),
// loaded in one extra clock (stallO). Without them the path RAM -> instruction -> register file -> unit
// (e.g. FPAdder's exponent logic, 63.7 ns) -> result counted as ONE clock; the result is only used clocks later.
// O5: code from the PSRAM cache (r5_cache): codeok = 0 says the instruction fetched at the last edge is not there
// (a miss). Then `cwait`: the decoder gets a never-taken branch (no effect), everything stalls with pcmux = PC (the
// cache re-reads PC), and the next clock looks at codebus again (fresh stays 1). cwait goes out to the cache.

module RISC5F(
input clk, rst, stallX,
input [31:0] inbus, codebus,
output [23:0] adr,
output rd, wr, ben,
output [31:0] outbus,
output ldw,  // F1: a load in its first clock (r5_tang makes stallX from it)
output stw,  // O3: a store in its first clock (r5_tang holds stallX for a PSRAM store)
output bw,  // O3: a byte load/store, not gated by stallX (ben is)
input codeok,  // O5: codebus is valid (r5_tang: 1 outside the PSRAM)
output cwait);  // O5: waiting for an instruction (a cache miss)

localparam StartAdr = 22'h3FF800;

reg [21:0] PC;
reg [31:0] IR;  // instruction register
reg N, Z, C, OV;  // condition flags 
reg [31:0] R [0:15];  // array of 16 registers
reg [31:0] H;  // aux register
reg stall1, PMsel;
reg fresh;  // F1: codebus holds the instruction fetched at the last edge
reg [31:0] opB, opC0, opC1;  // F2: operands of the multi-clock units
reg opv;  // F2: the operand registers hold this instruction's operands
wire mop, stallO;  // F2

wire [31:0] ins, pmout;
wire [21:0] pcmux, nxpc;
wire cond, S;
wire sa, sb, sc;

wire p, q, u, v, w;  // instruction fields
wire [3:0] op, ira, ira0, irb, irc;
wire [2:0] cc;
wire [15:0] imm;
wire [19:0] off;
wire [23:0] offL;

wire regwr;
wire stall, stallL, stallM, stallD, stallFA, stallFM, stallFD;
wire [1:0] sc1, sc0;  // shift counts

wire a0, a1, a2, a3;
wire [7:0] inbusL, outbusB0, outbusB1, outbusB2, outbusB3;
wire [23:0] inbusH;

wire [31:0] A, B, C0, C1, aluRes, regmux;
wire [31:0] s1, s2, s3, t1, t2, t3;
wire [31:0] quotient, remainder;
wire [63:0] product;
wire [31:0] fsum, fprod, fquot;

wire MOV, LSL, ASR, ROR, AND, ANN, IOR, XOR;  // operation signals
wire ADD, SUB, MUL, DIV; wire FAD, FSB, FML, FDV;
wire LDR, STR, BR;

r5_prom PM (.adr(pcmux[9:0]), .data(pmout), .clk(clk));  // O8: 1024 words (rtl/r5_prom.v)

// F2: run only when opv, operands from opB/opC0/opC1 (Wirth: run(MUL) .x(B) .y(C1), etc.)
Multiplier mulUnit (.clk(clk), .run(MUL & opv), .stall(stallM),
   .u(~u), .x(opB), .y(opC1), .z(product));

Divider divUnit (.clk(clk), .run(DIV & opv), .stall(stallD),
   .u(~u), .x(opB), .y(opC1), .quot(quotient), .rem(remainder));

FPAdder fpaddx (.clk(clk), .run((FAD|FSB) & opv), .u(u), .v(v), .stall(stallFA),
   .x(opB), .y({FSB^opC0[31], opC0[30:0]}), .z(fsum));

FPMultiplier fpmulx (.clk(clk), .run(FML & opv), .stall(stallFM),
   .x(opB), .y(opC0), .z(fprod));

FPDivider fpdivx (.clk(clk), .run(FDV & opv), .stall(stallFD),
   .x(opB), .y(opC0), .z(fquot));

assign cwait = fresh & ~PMsel & ~codeok;  // O5
assign ins = PMsel ? pmout : fresh ? (codeok ? codebus : 32'hEF000000) : IR;  // decoding  F1: was PMsel ? pmout : IR
  // O5: EF000000H = branch never (no register, flag, memory or PC effect)
assign p = ins[31];
assign q = ins[30];
assign u = ins[29];
assign v = ins[28];
assign w = ins[16];
assign cc  = ins[26:24];
assign ira = ins[27:24];
assign irb = ins[23:20];
assign op  = ins[19:16];
assign irc = ins[3:0];
assign imm = ins[15:0];   // reg instr.
assign off = ins[19:0];   // mem instr.
assign offL = ins[23:0];  // branch instr.

assign MOV = ~p & (op == 0);
assign LSL = ~p & (op == 1);
assign ASR = ~p & (op == 2);
assign ROR = ~p & (op == 3);
assign AND = ~p & (op == 4);
assign ANN = ~p & (op == 5);
assign IOR = ~p & (op == 6);
assign XOR = ~p & (op == 7);

assign ADD = ~p & (op == 8);
assign SUB = ~p & (op == 9);
assign MUL = ~p & (op == 10);
assign DIV = ~p & (op == 11);
assign FAD = ~p & (op == 12);
assign FSB = ~p & (op == 13);
assign FML = ~p & (op == 14);
assign FDV = ~p & (op == 15);

assign LDR = p & ~q & ~u;
assign STR = p & ~q & u;
assign BR = p & q;

assign A = R[ira0];  // register data signals
assign B = R[irb];
assign C0 = R[irc];

// Arithmetic-logical unit (ALU)
assign ira0 = BR ? 15 : ira;
assign C1 = q ? {{16{v}}, imm} : C0;
// O9r: the 20-bit offset sign-extended (Wirth: {4'b0, off}, right only with 1 MB, where adr[23:20] of a memory
// address is not decoded: B + (-8) gave B + 0FFFF8H; with the 4 MB PSRAM that is another place, Oberon trapped)
assign adr = stallL ? B[23:0] + {{4{off[19]}}, off} : {pcmux, 2'b00};
assign rd = LDR & ~stallX & ~stall1;
assign wr = STR & ~stallX & ~stall1;
assign ben = p & ~q & v & ~stallX & ~stall1;  // byte enable

assign sc0 = C1[1:0];
assign sc1 = C1[3:2];

// shifter for ASR and ROR
assign s1 = (sc0 == 3) ? {(w ? B[2:0] : {3{B[31]}}), B[31:3]} :
    (sc0 == 2) ? {(w ? B[1:0] : {2{B[31]}}), B[31:2]} :
    (sc0 == 1) ? {(w ? B[0] : B[31]), B[31:1]} : B;
assign s2 = (sc1 == 3) ? {(w ? s1[11:0] : {12{s1[31]}}), s1[31:12]} :
    (sc1 == 2) ? {(w ? s1[7:0] : {8{s1[31]}}), s1[31:8]} :
    (sc1 == 1) ? {(w ? s1[3:0] : {4{s1[31]}}), s1[31:4]} : s1;
assign s3 = C1[4] ? {(w ? s2[15:0] : {16{s2[31]}}), s2[31:16]} : s2;

// shifter for LSL
assign t1 = (sc0 == 3) ? {B[28:0], 3'b0} :
    (sc0 == 2) ? {B[29:0], 2'b0} :
    (sc0 == 1) ? {B[30:0], 1'b0} : B;
assign t2 = (sc1 == 3) ? {t1[19:0], 12'b0} :
    (sc1 == 2) ? {t1[23:0], 8'b0} :
    (sc1 == 1) ? {t1[27:0], 4'b0} : t1;
assign t3 = C1[4] ? {t2[15:0], 16'b0} : t2;

assign aluRes =
  MOV ? (q ?
    (~u ? {{16{v}}, imm} : {imm, 16'b0}) :
    (~u ? C0 : (~v ? H : {N, Z, C, OV, 20'b0, 8'h50}))) :
  LSL ? t3 :
  (ASR|ROR) ? s3 :
  AND ? B & C1 :
  ANN ? B & ~C1 :
  IOR  ? B | C1 :
  XOR ? B ^ C1 :
  ADD ? B + C1 + (u & C) :
  SUB ? B - C1 - (u & C) :
  MUL ? product[31:0] :
  DIV ? quotient :
 (FAD|FSB) ? fsum :
  FML ? fprod :
  FDV ? fquot :
  0;
  
assign regwr = ~p & ~stall | (LDR & ~stallX & ~stall1) | (BR & cond & v & ~stallX);
assign a0 = ~adr[1] & ~adr[0];
assign a1 = ~adr[1] & adr[0];
assign a2 = adr[1] & ~adr[0];
assign a3 = adr[1] & adr[0];
assign inbusL = (~ben | a0) ? inbus[7:0] :
  a1 ? inbus[15:8] : a2 ? inbus[23:16] : inbus[31:24];
assign inbusH = ~ben ? inbus[31:8] : 24'b0;
assign regmux = LDR ? {inbusH, inbusL} : (BR & v) ? {8'b0, nxpc, 2'b0} : aluRes;

assign outbusB0 = A[7:0];
assign outbusB1 = ben & a1 ? A[7:0] : A[15:8];
assign outbusB2 = ben & a2 ? A[7:0] : A[23:16];
assign outbusB3 = ben & a3 ? A[7:0] : A[31:24];
assign outbus = {outbusB3, outbusB2, outbusB1, outbusB0};

// Control unit CU
assign S = N ^ OV;
assign nxpc = PC + 1;
assign cond = ins[27] ^
  ((cc == 0) & N | // MI, PL
   (cc == 1) & Z | // EQ, NE
   (cc == 2) & C | // CS, CC
   (cc == 3) & OV | // VS, VC
   (cc == 4) & (C|Z) | // LS, HI
   (cc == 5) & S | // LT, GE
   (cc == 6) & (S|Z) | // LE, GT
   (cc == 7)); // T, F

assign pcmux = ~rst ? StartAdr :
  stall ? PC :
  (BR & cond & u) ? offL[21:0] + nxpc :
  (BR & cond & ~u) ? C0[23:2] : nxpc;
  
assign sa = aluRes[31];
assign sb = B[31];
assign sc = C1[31];

assign mop = MUL | DIV | FAD | FSB | FML | FDV;  // F2
assign stallO = mop & ~opv;  // F2: the clock that loads the operand registers
assign stall = stallL | stallM | stallD | stallX | stallFA | stallFM | stallFD | stallO | cwait;  // F2: + stallO, O5: + cwait
assign stallL = (LDR|STR) & ~stall1;
assign ldw = LDR & ~stall1;  // F1
assign stw = STR & ~stall1;  // O3
assign bw = p & ~q & v;  // O3

always @ (posedge clk) begin
  PC <= pcmux;
  PMsel <= ~rst | (pcmux[21:12] == 10'h3FF);
  IR <= ins;  // F1: was stall ? IR : codebus
  fresh <= ~stall | cwait;  // F1: after a clock without stall, the RAM output is the next instruction; O5: or a re-read of PC
  opB <= B; opC0 <= C0; opC1 <= C1;  // F2 (constant while the instruction stalls)
  opv <= mop & stall;  // F2: set after the operand clock, cleared after the result clock
  stall1 <= stallX ? stall1 : stallL;
  R[ira0] <= regwr ? regmux : A;
  N <= regwr ? regmux[31] : N;
  Z <= regwr ? (regmux == 0) : Z;
  C <= ADD ? (~sb&sc&~sa) | (sb&sc&sa) | (sb&~sa) :
	 SUB ? (~sb&sc&~sa) | (sb&sc&sa) | (~sb&sa) : C;
  OV <= ADD ? (sa&~sb&~sc) | (~sa&sb&sc): 
	 SUB ? (sa&~sb&sc) | (~sa&sb&~sc) : OV;
  H <= MUL ? product[63:32] : DIV ? remainder : H;
end 
endmodule 
