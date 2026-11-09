`timescale 1ns / 1ps
// tb_psram.v - OBERON_RISC5_FAST O3: r5_psram against tb/hyperram_model.v, driven like r5_tang drives it (toggle
// handshake from a 16.875 MHz CPU clock; controller 54 MHz from another source, so the clocks are unrelated).
// Parameters LC, FIXED, TCKD of the model (run_rf.sh runs several): the controller must measure the latency
// itself. O5: transactions are lines of 8 words. Writes 128 lines (a pattern from the address), reads them back
// (scattered order, so line addresses must be right); status: ready, no err_to/err_lat, data cycle = 2 + latency,
// transactions counted; the model: no setup / CS-time / register-space violations.
// Last line: "PSRAM TB PASS ..." or "PSRAM TB FAIL ...".
module tb_psram #(parameter LC = 6, parameter FIXED = 1, parameter real TCKD = 3.0);
    reg clk = 1'b0, mclk = 1'b0;
    always #29.630 clk = ~clk;                  // CPU 16.875 MHz
    always #9.25 mclk = ~mclk;                  // controller ~54 MHz (not locked to the CPU clock)
    reg mrst = 1'b1;

    reg        req_t = 1'b0, rw = 1'b0;
    reg [16:0] ladr = 17'd0;
    reg [255:0] wline = 256'd0;
    wire       ack_t;
    wire [255:0] rline;
    wire [31:0] status;
    wire ck, cs_n, reset_n, rwds;
    wire [7:0] dq;
    r5_psram #(.PWR_CLKS(300), .RST_CLKS(20)) dut (.clk(mclk), .rst(mrst), .req_t(req_t), .rw(rw), .ladr(ladr),
        .wline(wline), .ack_t(ack_t), .rline(rline), .status(status),
        .ck(ck), .cs_n(cs_n), .reset_n(reset_n), .dq(dq), .rwds(rwds));
    hyperram_model #(.LC(LC), .FIXED(FIXED), .TCKD(TCKD)) ram (.ck(ck), .cs_n(cs_n), .reset_n(reset_n),
        .dq(dq), .rwds(rwds));

    // the CPU side: toggle, wait for the synchronised answer (2 flip-flops), as r5_cache
    reg a1 = 1'b0, a2 = 1'b0;
    always @(posedge clk) begin a1 <= ack_t; a2 <= a1; end
    task access(input r, input [16:0] a, input [255:0] d, output [255:0] q);
        begin
            @(posedge clk);
            rw <= r; ladr <= a; wline <= d; req_t <= ~req_t;
            @(posedge clk);
            while (a2 != req_t) @(posedge clk);
            q = rline;
        end
    endtask

    function [255:0] pat(input [16:0] a);
        integer w;
        reg [19:0] x;
        begin
            for (w = 0; w < 8; w = w + 1) begin
                x = {a, w[2:0]};
                pat[32 * w +: 32] = {x[7:0] ^ 8'h5A, ~x[11:4], x[3:0], x[19:16], x[15:8] + 8'h33};
            end
        end
    endfunction

    integer i, bad = 0, n = 0;
    reg [255:0] q;
    reg [16:0] la;
    initial begin
        repeat (10) @(posedge mclk);
        mrst = 1'b0;
        // a request before the controller is ready waits (the CPU may access the PSRAM right after reset)
        access(1'b0, 17'd7, pat(17'd7), q);
        access(1'b1, 17'd7, 0, q);
        if (q !== pat(17'd7)) begin bad = bad + 1; $display("FAIL early line: %h", q); end
        for (i = 0; i < 128; i = i + 1) access(1'b0, i * 37 + 100, pat(i * 37 + 100), q);
        for (i = 0; i < 128; i = i + 1) begin
            la = ((i * 53) % 128) * 37 + 100;
            access(1'b1, la, 0, q);
            if (q !== pat(la)) begin
                bad = bad + 1;
                if (bad < 5) $display("FAIL line %0d: %h, want %h", la, q, pat(la));
            end
        end
        n = 2 + 256;
        $display("status %h: ready %b err_to %b err_lat %b rwds_ca %b data cycle %0d transactions %0d; model: %0d half-words read %0d written, %0d violations",
            status, status[31], status[30], status[29], status[28], status[23:16], status[15:0],
            ram.nrd, ram.nwr, ram.viol);
        if (status[31] !== 1'b1 || status[30] || status[29]) bad = bad + 1;
        if (status[23:16] != 2 + LC * (FIXED ? 2 : 1)) begin bad = bad + 1; $display("FAIL data cycle"); end
        if (status[15:0] != n) begin bad = bad + 1; $display("FAIL transactions %0d, want %0d", status[15:0], n); end
        if (ram.viol != 0) bad = bad + 1;
        if (bad == 0) $display("PSRAM TB PASS LC=%0d FIXED=%0d TCKD=%0.1f: %0d line transactions, data cycle %0d", LC, FIXED, TCKD, n, status[23:16]);
        else          $display("PSRAM TB FAIL LC=%0d FIXED=%0d TCKD=%0.1f: %0d errors", LC, FIXED, TCKD, bad);
        $finish;
    end
    initial begin #20_000_000; $display("PSRAM TB FAIL: timeout"); $finish; end
endmodule
