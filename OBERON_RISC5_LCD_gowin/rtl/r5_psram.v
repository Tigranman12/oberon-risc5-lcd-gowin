`timescale 1ns / 1ps
// r5_psram.v - OBERON_RISC5_FAST O3: one channel (4 MB) of the GW1NR-9's in-package HyperRAM for RISC5 (PLAN.md
// F-D9); O5 (F-D11): every transaction moves one cache line of 8 words (32 bytes) for rtl/r5_cache.v. Own controller: Gowin's PSRAM_HS core is encrypted and cannot be simulated here.
//   Clock: clk (54 MHz, its own rPLL); PSRAM CK = clk / 4 = 13.5 MHz. Every pin is a plain register: CK is high in the
//   periods 4c+1 and 4c+2 of clock cycle c, a data byte is put out one period before the CK edge that takes it
//   (centred: 18.5 ns before and after), read bytes are sampled one period after the CK edge that sent them.
//   A transaction: CS low, 3 cycles of command/address (CA, 48 bits), latency, 16 cycles of data (32 bytes = 16
//   half-words, linear burst; CS low ~2.3 us < 4 us), CS high, then at least 4 periods idle (74 ns, recovery).
//   O5: the bytes go out of / come into shift registers (no byte multiplexer on the 54 MHz paths).
//   Latency is not assumed: after power-up (reset pulse, 200 us wait) one read measures the cycle in which the
//   chip starts its data (RWDS goes from low, during the latency, to high with the first byte); writes put their data in that cycle. The chip's
//   RWDS during CA (2x latency) is kept from that read; a later CA with a different RWDS sets err_lat (the chip
//   would be in variable-latency mode, which this controller does not handle). No data within 100 cycles:
//   err_to, the read returns 0.
//   Bytes on the wire: word w of the line = half-words 2w (its bits 15:0) and 2w+1 (31:16), each upper byte first
//   (as O3's single words); lines are written whole (RWDS low = no byte masked).
//   CPU side: a toggle handshake (req_t from the CPU clock, synchronised here; ack_t := req_t when done, with
//   rline already stable). The CPU side holds rw, ladr, wline stable from its toggle to the answer.
//   status = {ready, err_to, err_lat, rwds_ca, 4'b0, data cycle (8), transactions (16)} for the I/O register.
module r5_psram #(parameter PWR_CLKS = 13500, parameter RST_CLKS = 68) (   // at 54 MHz: 250 us, 1.3 us
    input  wire        clk, rst,          // 54 MHz and its reset (active high)
    input  wire        req_t, rw,          // rw = 1: read
    input  wire [16:0] ladr,               // line address (32 bytes) in the 4 MB
    input  wire [255:0] wline,             // word i = wline[32i +: 32]
    output reg         ack_t = 1'b0,
    output wire [255:0] rline,             // the last line read, same layout
    output wire [31:0] status,
    output reg         ck = 1'b0, cs_n = 1'b1, reset_n = 1'b0,
    inout  wire [7:0]  dq,
    inout  wire        rwds
);
    // O6: every pin has its own register next to it (IOB: GowinSynthesis/PnR place a register that drives a pin
    // or is driven by one, alone, into the pin's I/O block): one tristate control per DQ pin, and the inputs are
    // sampled into dq_i / rwds_i at every edge and used one clock later (kd = the period they were sampled in).
    // Before, the samples went into fabric registers and the timing to the pins changed with the placement: one
    // build read only timeouts.
    reg [7:0] dq_o = 8'd0;
    (* syn_preserve = 1 *) reg [7:0] dq_t = 8'hFF;      // 1 = DQ pin j not driven
    reg       rwds_o = 1'b0;
    (* syn_preserve = 1 *) reg rwds_t = 1'b1;
    reg [7:0] dq_i = 8'd0;
    reg       rwds_i = 1'b0;
    genvar gi;
    generate for (gi = 0; gi < 8; gi = gi + 1) begin : dqp
        assign dq[gi] = dq_t[gi] ? 1'bz : dq_o[gi];
    end endgenerate
    assign rwds = rwds_t ? 1'bz : rwds_o;
    always @(posedge clk) begin dq_i <= dq; rwds_i <= rwds; end

    // request from the CPU clock
    reg r1 = 1'b0, r2 = 1'b0;
    always @(posedge clk) begin r1 <= req_t; r2 <= r1; end

    localparam [2:0] S_PWR = 0, S_WAIT = 1, S_IDLE = 2, S_RUN = 3, S_GAP = 4;
    reg [2:0]  st = S_PWR;
    reg [13:0] t = 14'd0;
    reg        ready = 1'b0, err_to = 1'b0, err_lat = 1'b0, rwds_ca = 1'b0, cal = 1'b0;
    reg [7:0]  dcyc = 8'd0;                // data cycle measured by the calibration read
    reg [8:0]  kw0 = 9'd0, kw1 = 9'd0;     // O6: 4 dcyc - 1, 4 dcyc + 63: the write window in periods k (no adder
                                           // on the 54 MHz path k -> window -> shift enable)
    reg [15:0] nx = 16'd0;
    assign status = {ready, err_to, err_lat, rwds_ca, 4'b0, dcyc, nx};

    reg        op_rd;
    reg [295:0] sh;                        // out: CA bytes 1..5, then the 32 data bytes (top byte next)
    reg [255:0] rsh = 256'd0;              // in: the bytes read, first byte at the top
    reg [8:0]  k;                          // period in the transaction (pins show period k)
    reg [8:0]  kd = 9'd0;                  // O6: the period whose inputs dq_i / rwds_i hold
    reg        cap;                        // read: bytes are coming
    reg [5:0]  nb;                         // read: bytes taken
    reg        rca;                        // RWDS during this CA
    reg        rwp;                        // read: RWDS at the last falling-edge sample
    wire [6:0] c  = k[8:2];                // CK cycle
    wire [6:0] cd = kd[8:2];               // ... of the inputs in dq_i / rwds_i
    wire [1:0] phd = kd[1:0];

    // stream byte b (0..31) = word b/4, lane (b mod 4) xor 1 (each half-word's upper byte first)
    wire [255:0] wst;
    genvar g;
    generate for (g = 0; g < 32; g = g + 1) begin : perm
        assign wst[255 - 8 * g -: 8]                            = wline[32 * (g / 4) + 8 * ((g % 4) ^ 1) +: 8];
        assign rline[32 * (g / 4) + 8 * ((g % 4) ^ 1) +: 8] = rsh[255 - 8 * g -: 8];
    end endgenerate
    wire [47:0] ca_rw = {rw, 1'b0, 1'b1, 11'd0, ladr, 1'b0, 13'd0, 3'd0};   // half-word address {ladr, 0000}

    reg [8:0] kn;
    reg [6:0] cn;
    reg [1:0] pn;
    always @(posedge clk) begin
        if (rst) begin
            st <= S_PWR; t <= 14'd0; reset_n <= 1'b0; cs_n <= 1'b1; ck <= 1'b0; dq_t <= 8'hFF; rwds_t <= 1'b1;
            ready <= 1'b0; err_to <= 1'b0; err_lat <= 1'b0; cal <= 1'b0; nx <= 16'd0; ack_t <= r2;
        end else case (st)
            S_PWR: begin                                   // reset pulse
                t <= t + 14'd1;
                if (t == RST_CLKS) begin reset_n <= 1'b1; t <= 14'd0; st <= S_WAIT; end
            end
            S_WAIT: begin                                  // 200 us, then the calibration read of word 0
                t <= t + 14'd1;
                if (t == PWR_CLKS) begin
                    cal <= 1'b1; op_rd <= 1'b1; sh <= {40'd0, 256'd0};           // read of line 0
                    k <= 9'd0; kd <= 9'd0; cap <= 1'b0; nb <= 6'd0;
                    cs_n <= 1'b0; ck <= 1'b0; dq_t <= 8'h00; dq_o <= 8'hA0; rwds_t <= 1'b1;
                    st <= S_RUN;
                end
            end
            S_IDLE: if (r2 != ack_t) begin
                op_rd <= rw;
                // CA: R/W, memory space, linear burst, half-word address: [44:16] = upper bits, [2:0] = lower
                sh <= {ca_rw[39:0], wst};
                k <= 9'd0; kd <= 9'd0; cap <= 1'b0; nb <= 6'd0;
                cs_n <= 1'b0; ck <= 1'b0; dq_t <= 8'h00; rwds_t <= 1'b1;
                dq_o <= ca_rw[47:40];                       // first CA byte (period 0)
                st <= S_RUN;
            end
            S_RUN: begin
                kn = k + 9'd1; cn = kn[8:2]; pn = kn[1:0];
                k <= kn; kd <= k;
                ck <= (pn == 2'd1) || (pn == 2'd2);
                // ---- outputs for period kn ----
                // period kn = k + 1: CA while kn < 12 (k < 11), write data while 4 dcyc <= kn < 4 dcyc + 64;
                // a byte goes out in the periods before CK edges (kn even = k odd)
                if (k < 9'd11) begin
                    dq_t <= 8'h00; rwds_t <= 1'b1;
                    if (k[0]) begin dq_o <= sh[295:288]; sh <= {sh[287:0], 8'd0}; end
                end else if (!op_rd && k >= kw0 && k < kw1) begin
                    dq_t <= 8'h00; rwds_t <= 1'b0; rwds_o <= 1'b0;
                    if (k[0]) begin dq_o <= sh[295:288]; sh <= {sh[287:0], 8'd0}; end
                end else begin
                    dq_t <= 8'hFF; rwds_t <= 1'b1;
                end
                // ---- inputs of period kd, sampled at its end (18.5 ns after the CK edge that sent them) ----
                if (cd == 7'd1 && phd == 2'd1) rca <= rwds_i;         // the chip's RWDS during CA
                if (phd == 2'd3) rwp <= rwds_i;
                if (op_rd && cd >= 3) begin
                    if (phd == 2'd1 && !cap && rwds_i && !rwp) begin  // first byte: RWDS low -> high
                        cap <= 1'b1; nb <= 6'd1; rsh <= {rsh[247:0], dq_i};
                        if (cal) begin dcyc <= {1'b0, cd}; rwds_ca <= rca; kw0 <= {cd, 2'b00} - 9'd1; kw1 <= {cd, 2'b00} + 9'd63; end
                    end else if (cap && nb < 6'd32 && (phd == 2'd1 || phd == 2'd3)) begin
                        nb <= nb + 6'd1; rsh <= {rsh[247:0], dq_i};
                    end
                end
                // ---- end ----
                if ((op_rd && cap && nb == 6'd31 && phd == 2'd3) ||               // 32nd byte taken
                    (!op_rd && k == kw1) ||                                        // 16th data cycle sent (O6)
                    (c == 7'd100)) begin                                           // no data: time out
                    if (op_rd && !(cap && nb == 6'd31)) begin err_to <= 1'b1; rsh <= 256'd0; end
                    if (!cal && rca != rwds_ca && c >= 2) err_lat <= 1'b1;
                    cs_n <= 1'b1; ck <= 1'b0; dq_t <= 8'hFF; rwds_t <= 1'b1;
                    t <= 14'd0; st <= S_GAP;
                end
            end
            S_GAP: begin                                   // CS high >= 4 periods (74 ns), then answer
                t <= t + 14'd1;
                if (t == 14'd3) begin
                    if (cal) begin cal <= 1'b0; ready <= 1'b1; end
                    else begin ack_t <= r2; nx <= nx + 16'd1; end
                    st <= S_IDLE;
                end
            end
            default: st <= S_PWR;
        endcase
    end
endmodule
