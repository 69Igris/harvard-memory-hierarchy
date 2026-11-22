// ============================================================================
// unicache_top.v  -  Von Neumann memory HIERARCHY (Phase II, BASELINE)
//
//   +-----------+  i_addr  +-----------+         +--------------+   +----------+
//   |           |--------->| FETCH/DATA|  ONE    |  unified L1  |   | main_mem |
//   | cpu_core  |  d_addr  |  arbiter  |-------->|  cache (WT + |-->| 8 KB,LAT |
//   |           |--------->|  (+ IR)   |  port   |  write buf)  |   |code+data |
//   +-----------+          +-----------+         +--------------+   +----------+
//
// Same core, same main memory and the same TOTAL L1 capacity as
// modharvard_top.v, but the L1 is a single, single-ported unified cache.
// Instruction fetch and load/store therefore take turns on the cache port
// (the Phase I structural hazard, now at L1 level) and code and data also
// compete for the same cache lines (conflict misses).
//
// NOCACHE = 1 gives the "flat" Von Neumann machine: one slow shared memory,
// no cache at all - the classic Von Neumann bottleneck.
// ============================================================================
`include "defines.vh"

module unicache_top #(
    parameter CODE_INIT  = "program.hex",
    parameter DATA_INIT  = "",
    parameter LAT        = 4,
    parameter U_SETS     = 32,
    parameter LINE_WORDS = 4,
    parameter NOCACHE    = 0
)(
    input  wire        clk,
    input  wire        rst,
    output wire        halted,
    output wire [31:0] halt_code,
    output wire [31:0] out_reg,
    output wire        bus_error,
    output wire        illegal
);
    localparam US = NOCACHE ? 1 : U_SETS;
    localparam LW = NOCACHE ? 1 : LINE_WORDS;
    localparam S_FETCH = 1'b0, S_DATA = 1'b1;

    reg         state;
    reg  [31:0] ir;

    wire [31:0] i_addr, d_addr, d_wdata, d_rdata_core;
    wire        d_read, d_write, d_wreq, is_mem, retire, core_illegal;
    wire        core_stall;

    // ---------------- unified cache port
    wire        in_data = (state == S_DATA);
    wire        c_stall, c_hit, wb_empty;
    wire [31:0] c_rdata;
    wire        sel_imem, sel_dmem, sel_io;
    wire        sel_mem = sel_imem | sel_dmem;

    wire        c_rd   = in_data ? (d_read & sel_mem) : ~halted;
    wire        c_wr   = in_data ? (d_wreq & sel_mem) : 1'b0;
    wire [31:0] c_addr = in_data ? d_addr : i_addr;

    wire        io_wait = in_data & sel_io & ~wb_empty;
    wire        port_commit = ~halted & ~c_stall & ~io_wait;

    wire [31:0] instr_in = in_data ? ir : c_rdata;

    // FETCH: stall on miss, and stall one extra cycle for every ld/st
    //        (the fetched word is latched into IR, the port moves to DATA)
    // DATA : stall on miss / full write buffer / I/O fence
    assign core_stall = halted | c_stall | io_wait | (~in_data & is_mem);
    assign illegal    = core_illegal & ~c_stall;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_FETCH;
            ir    <= 32'h0000_0013;
        end else if (port_commit) begin
            case (state)
                S_FETCH: if (is_mem) begin ir <= c_rdata; state <= S_DATA; end
                S_DATA :             state <= S_FETCH;
            endcase
        end
    end

    cpu_core u_core (
        .clk(clk), .rst(rst), .stall(core_stall),
        .i_addr(i_addr), .i_rdata(instr_in),
        .d_addr(d_addr), .d_wdata(d_wdata), .d_read(d_read), .d_write(d_write),
        .d_wreq(d_wreq), .d_rdata(d_rdata_core), .is_mem(is_mem), .retire(retire),
        .illegal(core_illegal)
    );

    addr_decoder #(.ALLOW_IMEM_DATA(1)) u_dec (
        .addr(d_addr), .req(in_data & (d_read | d_wreq)),
        .sel_imem(sel_imem), .sel_dmem(sel_dmem), .sel_io(sel_io),
        .bus_error(bus_error)
    );

    wire mem_we, mem_re, io_we, io_re;
    wire [31:0] io_rdata;
    rw_control u_rw (
        .mem_read(d_read), .mem_write(d_write),
        .sel_dmem(sel_mem), .sel_io(sel_io),
        .dmem_rdata(c_rdata), .io_rdata(io_rdata),
        .dmem_we(mem_we), .dmem_re(mem_re), .io_we(io_we), .io_re(io_re),
        .rdata_to_core(d_rdata_core)
    );

    // ---------------- unified L1 + main memory (single client, no arbiter)
    wire        m_req, m_we, m_busy, m_rvalid, m_done;
    wire [31:0] m_addr, m_wdata, m_rdata;
    wire [4:0]  m_len;
    wire        m_gnt = m_req & ~m_busy;
    wire        ev_read, ev_miss, ev_write, ev_write_hit, refilling, draining;

    l1_cache #(.SETS(US), .LINE_WORDS(LW), .WRITABLE(1), .NOCACHE(NOCACHE),
               .MISS_DATA(32'h0000_0013)) u_cache (
        .clk(clk), .rst(rst),
        .rd(c_rd), .wr(c_wr), .commit(port_commit), .addr(c_addr), .wdata(d_wdata),
        .rdata(c_rdata), .stall(c_stall), .hit(c_hit), .wb_empty(wb_empty),
        .mreq(m_req), .mwe(m_we), .maddr(m_addr), .mwdata(m_wdata), .mlen(m_len),
        .mgnt(m_gnt), .mrvalid(m_rvalid), .mdone(m_done), .mrdata(m_rdata),
        .refilling(refilling), .draining(draining),
        .ev_read(ev_read), .ev_read_miss(ev_miss),
        .ev_write(ev_write), .ev_write_hit(ev_write_hit)
    );

    main_mem #(.LAT(LAT), .CODE_INIT(CODE_INIT), .DATA_INIT(DATA_INIT)) u_mem (
        .clk(clk), .rst(rst),
        .req(m_gnt), .we(m_we), .addr(m_addr), .wdata(m_wdata), .len(m_len),
        .busy(m_busy), .rvalid(m_rvalid), .rdata(m_rdata), .done(m_done)
    );

    io_regs u_io (
        .clk(clk), .rst(rst), .we(io_we), .re(io_re), .addr(d_addr[7:0]),
        .wdata(d_wdata), .rdata(io_rdata), .out_reg(out_reg),
        .halted(halted), .halt_code(halt_code)
    );

    // ---------------- performance monitor
    wire run = ~halted;
    wire [31:0] cycles, instret, i_reads, i_misses, d_reads, d_misses, d_writes, d_write_hits;
    wire [31:0] c_imiss, c_dmiss, c_wbuf, c_io, c_struct, c_conflict, c_membusy, c_parallel;
    hier_perf u_perf (
        .clk(clk), .rst(rst), .enable(run), .retire(retire & run),
        .ev_i_read(ev_read & ~in_data), .ev_i_miss(ev_miss & ~in_data),
        .ev_d_read(ev_read &  in_data), .ev_d_miss(ev_miss &  in_data),
        .ev_d_write(ev_write), .ev_d_write_hit(ev_write_hit),
        .st_imiss (run & ~in_data & c_stall),
        .st_dmiss (run &  in_data & c_stall & c_rd),
        .st_wbuf  (run &  in_data & c_stall & c_wr),
        .st_io    (run & io_wait),
        .st_struct(run & ~in_data & ~c_stall & is_mem),
        .conflict(1'b0), .mem_busy(m_busy), .parallel(1'b0),
        .cycles(cycles), .instret(instret),
        .i_reads(i_reads), .i_misses(i_misses), .d_reads(d_reads), .d_misses(d_misses),
        .d_writes(d_writes), .d_write_hits(d_write_hits),
        .c_imiss(c_imiss), .c_dmiss(c_dmiss), .c_wbuf(c_wbuf), .c_io(c_io),
        .c_struct(c_struct), .c_conflict(c_conflict), .c_membusy(c_membusy),
        .c_parallel(c_parallel)
    );
endmodule
