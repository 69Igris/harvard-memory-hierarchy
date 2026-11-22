// ============================================================================
// l1_cache.v  -  Level-1 cache (direct-mapped), used as
//                  * instruction cache  (WRITABLE = 0)
//                  * data cache         (WRITABLE = 1)
//                  * unified cache      (WRITABLE = 1, in unicache_top.v)
//
// Organisation : SETS lines x LINE_WORDS words, direct-mapped.
// Hit path     : combinational (tag compare + data read in the same cycle),
//                so a hit costs nothing extra for the single-cycle core.
// Read miss    : the whole line is fetched from the shared main memory as one
//                burst (LINE_WORDS words); the core is stalled until the line
//                is valid, then the access hits.
// Writes       : write-through, no-write-allocate, through a 1-entry write
//                buffer. A store completes in 1 cycle if the buffer is empty;
//                the buffer drains to main memory in the background, in
//                parallel with execution. A read miss waits until the buffer
//                is empty, so a load can never see stale memory (RAW safe).
// NOCACHE = 1  : degenerate "no cache" mode used for the flat baselines -
//                1 line x 1 word whose valid bit is cleared every time the
//                word is consumed, so EVERY read goes to main memory.
//
// Address split (word address w = addr[31:2]):
//      offset = w % LINE_WORDS, index = (w / LINE_WORDS) % SETS,
//      tag    = w / (LINE_WORDS*SETS)    (only ADDR_BITS of address kept)
// ============================================================================
module l1_cache #(
    parameter SETS       = 16,
    parameter LINE_WORDS = 4,
    parameter WRITABLE   = 1,
    parameter NOCACHE    = 0,
    parameter ADDR_BITS  = 13,              // 8 KB physical space
    parameter MISS_DATA  = 32'h0000_0000    // value returned while missing
)(
    input  wire        clk,
    input  wire        rst,
    // ---------------- core side
    input  wire        rd,                  // read access this cycle
    input  wire        wr,                  // write access this cycle
    input  wire        commit,              // the access completes this cycle
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata,
    output wire        stall,               // access cannot complete this cycle
    output wire        hit,
    output wire        wb_empty,
    // ---------------- lower-level side (to mem_arbiter)
    output wire        mreq,
    output wire        mwe,
    output wire [31:0] maddr,
    output wire [31:0] mwdata,
    output wire [4:0]  mlen,
    input  wire        mgnt,
    input  wire        mrvalid,
    input  wire        mdone,
    input  wire [31:0] mrdata,
    // ---------------- status / events (for performance counters)
    output wire        refilling,
    output wire        draining,
    output wire        ev_read,             // committed read
    output wire        ev_read_miss,        // line refill started
    output wire        ev_write,            // committed write
    output wire        ev_write_hit         // committed write that hit a line
);
    localparam LOG_SETS = $clog2(SETS);
    localparam LOG_LINE = $clog2(LINE_WORDS);
    localparam TAGW     = ADDR_BITS - 2 - LOG_SETS - LOG_LINE;

    localparam S_IDLE = 2'd0, S_REFILL = 2'd1, S_DRAIN = 2'd2;

    // ---------------- storage
    reg [31:0]     data  [0:SETS*LINE_WORDS-1];
    reg [TAGW-1:0] tags  [0:SETS-1];
    reg [SETS-1:0] valid;

    // ---------------- address split
    wire [31:0] w      = {2'b00, addr[31:2]};
    wire [31:0] off    = w % LINE_WORDS;
    wire [31:0] idx    = (w / LINE_WORDS) % SETS;
    wire [31:0] tag32  = w / (LINE_WORDS * SETS);
    wire [TAGW-1:0] tag = tag32[TAGW-1:0];
    wire [31:0] line_base = (w - off) << 2;

    assign hit   = valid[idx] && (tags[idx] == tag);
    assign rdata = hit ? data[idx * LINE_WORDS + off] : MISS_DATA;

    // ---------------- write buffer (1 entry)
    reg        wb_valid;
    reg [31:0] wb_addr, wb_data;
    assign wb_empty = ~wb_valid;

    // ---------------- miss / drain FSM
    reg [1:0]  state;
    reg [31:0] r_idx;
    reg [TAGW-1:0] r_tag;
    reg [4:0]  beat;

    wire want_drain  = (WRITABLE != 0) && wb_valid;
    wire want_refill = rd && !hit;

    assign mreq   = (state == S_IDLE) && (want_drain || want_refill);
    assign mwe    = want_drain;
    assign maddr  = want_drain ? wb_addr : line_base;
    assign mwdata = wb_data;
    assign mlen   = want_drain ? 5'd1 : LINE_WORDS[4:0];

    assign stall  = (rd && !hit) || ((WRITABLE != 0) && wr && wb_valid);

    assign refilling    = (state == S_REFILL);
    assign draining     = (state == S_DRAIN);
    assign ev_read      = commit && rd;
    assign ev_read_miss = mgnt && !want_drain;
    assign ev_write     = (WRITABLE != 0) && commit && wr;
    assign ev_write_hit = ev_write && hit;


    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            valid    <= {SETS{1'b0}};
            wb_valid <= 1'b0;
            beat     <= 0;
        end else begin
            case (state)
                S_IDLE: if (mgnt) begin
                    if (want_drain) begin
                        state <= S_DRAIN;
                    end else begin
                        state      <= S_REFILL;
                        r_idx      <= idx;
                        r_tag      <= tag;
                        beat       <= 0;
                        valid[idx] <= 1'b0;      // line is being replaced
                    end
                end
                S_REFILL: begin
                    if (mrvalid) beat <= beat + 5'd1;
                    if (mdone) begin
                        valid[r_idx] <= 1'b1;
                        state        <= S_IDLE;
                    end
                end
                S_DRAIN: if (mdone) begin
                    wb_valid <= 1'b0;
                    state    <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase

            // ---- store: write-through via the buffer
            if (ev_write) begin
                wb_valid <= 1'b1;
                wb_addr  <= addr;
                wb_data  <= wdata;
            end

            // ---- "no cache" mode: forget the word once it has been used
            if (NOCACHE != 0 && commit && rd && state == S_IDLE)
                valid <= {SETS{1'b0}};
        end
    end

    // ---------------- data / tag arrays: ONE write port each, no reset,
    // so synthesis maps them to distributed RAM instead of flip-flops.
    // A refill beat and a store hit can never happen in the same cycle
    // (a store only completes while the FSM is idle).
    wire        refill_we = (state == S_REFILL) && mrvalid;
    wire        store_we  = ev_write && hit;
    wire [31:0] data_widx = refill_we ? (r_idx * LINE_WORDS + beat) : (idx * LINE_WORDS + off);
    wire [31:0] data_wval = refill_we ? mrdata : wdata;

    always @(posedge clk) begin
        if (refill_we || store_we)
            data[data_widx] <= data_wval;
        if (state == S_REFILL && mdone)
            tags[r_idx] <= r_tag;
    end
endmodule
