`timescale 1ns / 1ps
// r5_cache.v - OBERON_RISC5_FAST O5 (PLAN.md F-D11): a unified cache for the PSRAM (O6: at 0-3FFFFFH), in the
// CPU clock domain: instruction fetches, loads and stores all go through it, so code can run from the PSRAM and
// a program stored there (the monitor's l) is fetched from the same lines (no flush needed).
//   Direct mapped, write back, write allocate: 2^IW lines of 8 words. IW 8 = 8 KB (4 + 1 BSRAM: O5, and O6 on the
//   board); IW 10 = 32 KB (16 SDPB 8K x 2 + 1) was tried in O6: on the board fills into odd lines kept storing
//   bits of word w+1 in word w (0.3-25 % of the fills, moving with each placement) even with the measures below;
//   8 KB (2K x 8 BSRAM) had none in 3 MB tests. Address (byte, in the 4 MB): tag = [21:IW+5] (TW = 17 - IW
//   bits), index = [IW+4:5], word = [4:2].
//   Tag entry: {valid, dirty, tag}. Like r5_ram, both RAMs are read at the RISING edge with the CPU's address
//   (adr: the next instruction, or a load/store's address); the compare is in the clock after (r_adr = the address
//   read). hit = the line read is valid and its tag matches r_adr.
//   Miss (a fetch the CPU waits for: cwait, or a load/store in its second clock: dmiss): if the old line is dirty,
//   read its 8 words into wline and write it to the PSRAM; read the new line (r5_psram, toggle handshake); copy the
//   8 words into the data RAM, the tag {1, 0, tag} with the last one; one more clock re-reads adr (busy all along).
//   O6: 2 clocks per word in both copies, no RAM read during the fill, the fill's write port from falling-edge
//   registers (each one cut the board errors of the 32 KB cache; see below). Store hit:
//   the byte lanes are written and the tag gets dirty = 1.
//   Counters for I/O: misses (lines filled) and write-backs.
module r5_cache #(parameter IW = 8) (
    input  wire        clk,
    input  wire [23:0] adr,             // RISC5's address (byte)
    input  wire        cwait,           // RISC5 waits for an instruction (fetched at the last edge) that missed
    input  wire        dmiss_req,       // r5_tang: a PSRAM load/store in its second clock, and !hit
    input  wire        swr,             // store hit: write the byte lanes swe with wdata at adr
    input  wire [3:0]  swe,
    input  wire [31:0] wdata,
    output wire [31:0] rdata,           // the word read at the last edge
    output wire        hit,             // ... is in the cache (valid, tag matches r_adr)
    output wire        busy,            // a miss is being handled (the CPU stalls)
    output reg  [31:0] nmiss = 32'd0, nwb = 32'd0,
    // r5_psram (other clock: the handshake is synchronised here, the line buses are stable while it runs)
    output reg         req_t = 1'b0,
    output reg         rw = 1'b0,
    output reg  [16:0] ladr = 17'd0,
    output reg  [255:0] wline = 256'd0,
    input  wire        ack_t,
    input  wire [255:0] rline
);
    // ---- RAMs ----
    localparam TW = 17 - IW;
    localparam NW = 1 << (IW + 3);              // words
    reg [7:0]  d0 [0:NW-1];
    reg [7:0]  d1 [0:NW-1];
    reg [7:0]  d2 [0:NW-1];
    reg [7:0]  d3 [0:NW-1];
    reg [TW+1:0] tg [0:(1<<IW)-1];              // {valid, dirty, tag}
    integer i;
    initial for (i = 0; i < (1 << IW); i = i + 1) tg[i] = 0;   // all lines invalid (BSRAM starts at 0)

    localparam [2:0] S_IDLE = 0, S_WBR = 1, S_WB = 2, S_RD = 3, S_COPY = 4, S_LAST = 5;
    reg [2:0]  st = S_IDLE;
    reg [3:0]  cnt = 4'd0;
    reg [IW-1:0] midx = 0;
    reg [TW-1:0] mtag = 0;
    reg        a1 = 1'b0, a2 = 1'b0;

    // read port: the CPU's address, or the old line's words (S_WBR)
    // O6: a write-back reads word cnt[3:1] at cnt even and odd and takes it from q at the odd edge (q does not
    // change then; back to back, bits of word w+1 got into word w)
    wire [IW+2:0] ra = (st == S_WBR) ? {midx, cnt[3:1]} : adr[IW+4:2];
    // write port: the new line's words (S_COPY), or a store hit
    wire        cw = (st == S_COPY);
    // O6: a fill writes word cnt[3:1] at cnt even only: its address and data are set a clock before and kept a
    // clock after that edge (back to back, bits of word w+1 got into word w)
    //   ... and its address, data and enable come from registers loaded at the FALLING edge (cf_*): stable 29.6
    //   ns before and after the rising edge that writes (straight from the logic, the BSRAM took part of the
    //   next word's bits: placement-dependent, not in the timing report). Store hits keep the direct path.
    reg         cf_sel = 1'b0, cf_we = 1'b0;
    reg [IW+2:0] cf_wa = 0;
    reg [31:0]  cf_wd = 32'd0;
    wire [IW+2:0] wa = cf_sel ? cf_wa : adr[IW+4:2];
    wire [3:0]  we = cf_sel ? {4{cf_we}} : (swr ? swe : 4'b0000);
    reg  [31:0] rline_w;
    always @* case (cnt[3:1])
        3'd0: rline_w = rline[31:0];     3'd1: rline_w = rline[63:32];
        3'd2: rline_w = rline[95:64];    3'd3: rline_w = rline[127:96];
        3'd4: rline_w = rline[159:128];  3'd5: rline_w = rline[191:160];
        3'd6: rline_w = rline[223:192];  default: rline_w = rline[255:224];
    endcase
    wire [31:0] wd = cf_sel ? cf_wd : wdata;
    always @(negedge clk) begin
        cf_sel <= cw; cf_we <= cw & ~cnt[0]; cf_wa <= {midx, cnt[3:1]}; cf_wd <= rline_w;
    end

    // O6: no read during a fill (re = 0: q keeps its value; S_LAST re-reads). On the board a read during a fill
    // (the CPU's address: word 0 of the line being written) changed bits of the words written next to it: word
    // w got bits of word w+1 (words 0 / 2 / 4 of odd lines, ~25 % of the fills; the simulation and the timing
    // report show nothing). A store hit's read of its own word did no harm (32 KB of stores + loads: 0 errors).
    wire        re = ~cw;
    reg [TW+1:0] tq = 0;
    reg [23:0] r_adr = 24'd0;
    wire [31:0] q;
    generate if (IW == 10) begin : prim
        // 32 KB = 16 SDPB placed by hand (to have the read enable CEB), each 8K x 2: bits 2j+1:2j of every word,
        // byte lane j/4 writes it
        genvar j;
        for (j = 0; j < 16; j = j + 1) begin : b
            wire [31:0] dout;
            SDPB #(.READ_MODE(1'b0), .BIT_WIDTH_0(2), .BIT_WIDTH_1(2), .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000),
                   .RESET_MODE("SYNC")) ram (
                .DO(dout), .DI({30'd0, wd[2 * j +: 2]}), .BLKSELA(3'b000), .BLKSELB(3'b000),
                .ADA({wa, 1'b0}), .ADB({ra, 1'b0}), .CLKA(clk), .CLKB(clk), .CEA(we[j / 4]), .CEB(re),
                .OCE(1'b1), .RESETA(1'b0), .RESETB(1'b0));
            assign q[2 * j +: 2] = dout[1:0];
        end
    end else begin : inf
        reg [31:0] qr = 32'd0;
        always @(posedge clk) begin
            if (we[0]) d0[wa] <= wd[7:0];
            if (we[1]) d1[wa] <= wd[15:8];
            if (we[2]) d2[wa] <= wd[23:16];
            if (we[3]) d3[wa] <= wd[31:24];
            if (re) qr <= {d3[ra], d2[ra], d1[ra], d0[ra]};
        end
        assign q = qr;
    end endgenerate
    // tag RAM: read with adr's index; written with the fill's last word (valid, clean) or by a store hit (dirty)
    wire        tw = (cw && cnt == 4'd14) | swr;
    wire [IW-1:0] twa = cw ? midx : adr[IW+4:5];
    wire [TW+1:0] twd = cw ? {2'b10, mtag} : {2'b11, adr[21:IW+5]};
    always @(posedge clk) begin
        if (tw) tg[twa] <= twd;
        if (re) tq <= tg[adr[IW+4:5]];                 // O6: as the data RAM, no read during a fill
        r_adr <= adr;
    end
    assign rdata = q;
    assign hit   = tq[TW+1] && (tq[TW-1:0] == r_adr[21:IW+5]);
    assign busy  = (st != S_IDLE);

    // ---- miss handling ----
    always @(posedge clk) begin
        a1 <= ack_t; a2 <= a1;
        case (st)
            S_IDLE: if ((cwait | dmiss_req) && !hit) begin
                midx <= r_adr[IW+4:5]; mtag <= r_adr[21:IW+5]; cnt <= 4'd0;
                nmiss <= nmiss + 32'd1;
                if (tq[TW+1] && tq[TW]) begin                // the old line is dirty: write it back first
                    ladr <= {tq[TW-1:0], r_adr[IW+4:5]}; nwb <= nwb + 32'd1;
                    st <= S_WBR;
                end else begin
                    ladr <= r_adr[21:5]; rw <= 1'b1; req_t <= ~req_t;
                    st <= S_RD;
                end
            end
            S_WBR: begin                                     // word cnt[3:1] is read at cnt even and odd: q has
                cnt <= cnt + 4'd1;                           // it from the even edge on, taken at the odd one
                if (cnt[0]) wline[32 * cnt[3:1] +: 32] <= q;
                if (cnt == 4'd15) begin rw <= 1'b0; req_t <= ~req_t; st <= S_WB; end
            end
            S_WB: if (a2 == req_t) begin                     // written: now read the new line
                ladr <= {mtag, midx}; rw <= 1'b1; req_t <= ~req_t;
                st <= S_RD;
            end
            S_RD: if (a2 == req_t) begin cnt <= 4'd0; st <= S_COPY; end
            S_COPY: begin                                    // word cnt[3:1], written at cnt even
                cnt <= cnt + 4'd1;
                if (cnt == 4'd15) st <= S_LAST;
            end
            S_LAST: st <= S_IDLE;                            // this edge re-reads adr (data and tag are in)
            default: st <= S_IDLE;
        endcase
    end
endmodule
