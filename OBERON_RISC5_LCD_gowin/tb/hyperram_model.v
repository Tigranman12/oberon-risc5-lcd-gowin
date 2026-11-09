`timescale 1ns / 1ps
// hyperram_model.v - OBERON_RISC5_FAST O3: a behavioural HyperRAM (8-bit HyperBus, half-word addressed) for the
// testbenches of r5_psram, as the controller expects the GW1NR-9's in-package chip to behave:
//   CS low, 6 CA bytes on both CK edges (CA[47] = read, [46] = register space, [44:16] and [2:0] = address),
//   RWDS driven high during CA when the latency is doubled (FIXED = 1: always), data after LC (x2) cycles:
//   the first data byte is taken/sent at the rising CK edge of cycle 2 + latency (cycle 0 = first CA cycle).
//   Reads: TCKD ns after each CK edge, the next byte (upper byte of each half-word first), RWDS high with the
//   rising-edge byte and low with the falling-edge one, low during the latency; linear burst.
//   Writes: byte and RWDS (1 = mask) taken at each CK edge after the latency.
// Checks (counted in viol, printed): a DQ or RWDS change less than TSU ns before a CK edge that takes it,
// CS low longer than TCSM ns (the chip must refresh), a register-space access (the controller makes none).
module hyperram_model #(parameter LC = 6, parameter FIXED = 1, parameter TCKD = 3.0, parameter TSU = 2.0,
                        parameter TCSM = 4000.0, parameter AW = 16) (
    input  wire       ck, cs_n, reset_n,
    inout  wire [7:0] dq,
    inout  wire       rwds
);
    reg [15:0] mem [0:(1<<AW)-1];
    reg [7:0]  dq_d = 8'd0;
    reg        dq_e = 1'b0, rw_d = 1'b0, rw_e = 1'b0;
    assign dq   = dq_e ? dq_d : 8'hzz;
    assign rwds = rw_e ? rw_d : 1'bz;

    integer viol = 0, nrd = 0, nwr = 0;
    integer e;                                  // CK edge in this transaction (0 = first rising edge)
    reg [47:0] ca;
    reg        rd;
    reg [AW-1:0] ha;                            // half-word address
    integer    e0;                              // first data edge
    realtime   tcs, tdq = 0, trw = 0;
    always @(dq)   tdq = $realtime;
    always @(rwds) trw = $realtime;

    always @(negedge cs_n) if (reset_n) begin
        e = 0; ca = 48'd0; tcs = $realtime;
        dq_e <= 1'b0;
        rw_e <= #(TCKD) 1'b1; rw_d <= #(TCKD) (FIXED != 0);   // latency indicator during CA
    end
    always @(posedge cs_n) begin
        dq_e <= 1'b0; rw_e <= 1'b0;
        if ($realtime - tcs > TCSM) begin viol = viol + 1; $display("HYPERRAM: CS low %0t ns > %0t", $realtime - tcs, TCSM); end
    end

    always @(ck) if (!cs_n && reset_n && (ck === 1'b1 || e > 0)) begin
        if (e < 6) begin
            if ($realtime - tdq < TSU) begin viol = viol + 1; $display("HYPERRAM: CA byte %0d setup %0t ns", e, $realtime - tdq); end
            ca = {ca[39:0], dq};
            if (e == 5) begin
                rd = ca[47];
                ha = {ca[44:16], ca[2:0]};
                e0 = 2 * (2 + LC * ((FIXED != 0) ? 2 : 1));
                if ($test$plusargs("hdbg")) $display("HDBG %0t: %s ha %h", $realtime, rd ? "RD" : "WR", ha);
                if (ca[46]) begin viol = viol + 1; $display("HYPERRAM: register space access %h", ca); end
                rw_e <= #(TCKD) rd; rw_d <= #(TCKD) 1'b0;       // read: RWDS low during the latency; write: released
            end
        end else if (rd) begin
            if (e >= e0) begin                  // the byte of edge e, TCKD after it, edge-aligned with RWDS
                dq_e <= #(TCKD) 1'b1;
                dq_d <= #(TCKD) (((e - e0) % 2) == 0) ? mem[ha][15:8] : mem[ha][7:0];
                rw_d <= #(TCKD) (((e - e0) % 2) == 0);
                if (((e - e0) % 2) == 1) begin ha = ha + 1'b1; nrd = nrd + 1; end
            end
        end else if (e >= e0 && !rd) begin
            if ($realtime - tdq < TSU || $realtime - trw < TSU) begin
                viol = viol + 1; $display("HYPERRAM: write byte setup %0t / %0t ns", $realtime - tdq, $realtime - trw);
            end
            if (rwds !== 1'b1) begin
                if (((e - e0) % 2) == 0) mem[ha][15:8] = dq; else mem[ha][7:0] = dq;
            end
            if (((e - e0) % 2) == 1) begin ha = ha + 1'b1; nwr = nwr + 1; end
        end
        e = e + 1;
    end
endmodule
