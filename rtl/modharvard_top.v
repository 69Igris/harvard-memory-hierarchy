// ============================================================================
// modharvard_top.v  -  Modified-Harvard memory HIERARCHY (Phase II, PROPOSED)
//
//   +-----------+  i_addr   +---------+                +-------------+
//   |           |---------->|  L1 I$  |--miss/refill-->|             |
//   |           |<----------| (RO)    |                |  mem_arbiter|   +-----------+
//   | cpu_core  |           +---------+                |  (I first)  |-->| main_mem  |
//   |           |  d_addr   +---------+   +---------+  |             |   | 8 KB, LAT |
//   |           |---------->| decoder |-->|  L1 D$  |->|             |   | code+data |
//   |           |<-- r/w ---|  + r/w  |   | WT + WB |  +-------------+   +-----------+
//   +-----------+   ctrl    +---------+   +---------+
//                                |-> MMIO (uncached)
//
// The two L1 caches give the core SEPARATE instruction and data paths (an
// I-hit and a D-hit happen in the same cycle, like Phase I's Harvard design),
// while a single SHARED lower-level memory holds both code and data (one
// address space, like a Von Neumann machine). Fetch and data traffic only
// compete on misses and write-buffer drains, through mem_arbiter.
//
// Parameters
//   LAT       main-memory first-word latency (cycles)
//   I_SETS/D_SETS, LINE_WORDS   cache geometry
//   NOCACHE   1 = both L1s disabled ("flat" split-port machine on slow memory)
// ============================================================================
`include "defines.vh"

module modharvard_top #(
    parameter CODE_INIT  = "program.hex",
    parameter DATA_INIT  = "",
    parameter LAT        = 4,
    parameter I_SETS     = 16,
    parameter D_SETS     = 16,
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
    localparam IS = NOCACHE ? 1 : I_SETS;
    localparam DS = NOCACHE ? 1 : D_SETS;
    localparam LW = NOCACHE ? 1 : LINE_WORDS;

    // ---------------- core
    wire [31:0] i_addr, i_rdata, d_addr, d_wdata, d_rdata;
    wire        d_read, d_write, d_wreq, is_mem, retire, core_illegal;
    wire        core_stall;

    cpu_core u_core (
        .clk(clk), .rst(rst), .stall(core_stall),
        .i_addr(i_addr), .i_rdata(i_rdata),
        .d_addr(d_addr), .d_wdata(d_wdata), .d_read(d_read), .d_write(d_write),
        .d_wreq(d_wreq), .d_rdata(d_rdata), .is_mem(is_mem), .retire(retire),
        .illegal(core_illegal)
    );

    // ---------------- L1 instruction cache
    wire        i_stall, i_hit;
    wire        im_req, im_we, im_gnt, im_rvalid, im_done;
    wire [31:0] im_addr, im_wdata, m_rdata;
    wire [4:0]  im_len;
    wire        ev_i_read, ev_i_miss, i_refilling;
    wire        commit = ~core_stall;

    l1_cache #(.SETS(IS), .LINE_WORDS(LW), .WRITABLE(0), .NOCACHE(NOCACHE),
               .MISS_DATA(32'h0000_0013)) u_icache (
        .clk(clk), .rst(rst),
        .rd(~halted), .wr(1'b0), .commit(commit), .addr(i_addr), .wdata(32'h0),
        .rdata(i_rdata), .stall(i_stall), .hit(i_hit), .wb_empty(),
        .mreq(im_req), .mwe(im_we), .maddr(im_addr), .mwdata(im_wdata), .mlen(im_len),
        .mgnt(im_gnt), .mrvalid(im_rvalid), .mdone(im_done), .mrdata(m_rdata),
        .refilling(i_refilling), .draining(),
        .ev_read(ev_i_read), .ev_read_miss(ev_i_miss), .ev_write(), .ev_write_hit()
    );

    // ---------------- data side: decoder + read/write control
    // While the I-cache is missing, the "instruction" is a NOP placeholder,
    // so data-side requests are masked with ~i_stall.
    wire sel_imem, sel_dmem, sel_io;
    addr_decoder #(.ALLOW_IMEM_DATA(0)) u_dec (
        .addr(d_addr), .req((d_read | d_wreq) & ~i_stall),
        .sel_imem(sel_imem), .sel_dmem(sel_dmem), .sel_io(sel_io),
        .bus_error(bus_error)
    );

    wire dmem_we, dmem_re, io_we, io_re;
    wire [31:0] dcache_rdata, io_rdata;
    rw_control u_rw (
        .mem_read(d_read), .mem_write(d_write),
        .sel_dmem(sel_dmem), .sel_io(sel_io),
        .dmem_rdata(dcache_rdata), .io_rdata(io_rdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re), .io_we(io_we), .io_re(io_re),
        .rdata_to_core(d_rdata)
    );

    // ---------------- L1 data cache (write-through + write buffer)
    wire d_rd = d_read & sel_dmem;
    wire d_wr = d_wreq & sel_dmem;
    wire d_stall, d_hit, wb_empty;
    wire dm_req, dm_we, dm_gnt, dm_rvalid, dm_done;
    wire [31:0] dm_addr, dm_wdata;
    wire [4:0]  dm_len;
    wire ev_d_read, ev_d_miss, ev_d_write, ev_d_write_hit, d_refilling, d_draining;

    l1_cache #(.SETS(DS), .LINE_WORDS(LW), .WRITABLE(1), .NOCACHE(NOCACHE)) u_dcache (
        .clk(clk), .rst(rst),
        .rd(d_rd), .wr(d_wr), .commit(commit), .addr(d_addr), .wdata(d_wdata),
        .rdata(dcache_rdata), .stall(d_stall), .hit(d_hit), .wb_empty(wb_empty),
        .mreq(dm_req), .mwe(dm_we), .maddr(dm_addr), .mwdata(dm_wdata), .mlen(dm_len),
        .mgnt(dm_gnt), .mrvalid(dm_rvalid), .mdone(dm_done), .mrdata(m_rdata),
        .refilling(d_refilling), .draining(d_draining),
        .ev_read(ev_d_read), .ev_read_miss(ev_d_miss),
        .ev_write(ev_d_write), .ev_write_hit(ev_d_write_hit)
    );

    // I/O is uncached; it waits for the write buffer so that HALT/OUT are
    // ordered after every earlier store (acts as a memory fence).
    wire io_wait = sel_io & ~wb_empty;

    assign core_stall = halted | i_stall | d_stall | io_wait;
    assign illegal    = core_illegal & ~i_stall;

    // ---------------- shared lower level: arbiter + main memory
    wire        m_req, m_we, m_busy, m_rvalid, m_done, conflict;
    wire [31:0] m_addr, m_wdata;
    wire [4:0]  m_len;

    mem_arbiter #(.PRIO_I(1)) u_arb (
        .clk(clk), .rst(rst),
        .i_req(im_req), .i_we(im_we), .i_addr(im_addr), .i_wdata(im_wdata), .i_len(im_len),
        .i_gnt(im_gnt), .i_rvalid(im_rvalid), .i_done(im_done),
        .d_req(dm_req), .d_we(dm_we), .d_addr(dm_addr), .d_wdata(dm_wdata), .d_len(dm_len),
        .d_gnt(dm_gnt), .d_rvalid(dm_rvalid), .d_done(dm_done),
        .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wdata), .m_len(m_len),
        .m_busy(m_busy), .m_rvalid(m_rvalid), .m_done(m_done), .conflict(conflict)
    );

    main_mem #(.LAT(LAT), .CODE_INIT(CODE_INIT), .DATA_INIT(DATA_INIT)) u_mem (
        .clk(clk), .rst(rst),
        .req(m_req), .we(m_we), .addr(m_addr), .wdata(m_wdata), .len(m_len),
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
        .ev_i_read(ev_i_read), .ev_i_miss(ev_i_miss),
        .ev_d_read(ev_d_read), .ev_d_miss(ev_d_miss),
        .ev_d_write(ev_d_write), .ev_d_write_hit(ev_d_write_hit),
        .st_imiss (run & i_stall),
        .st_dmiss (run & ~i_stall & d_rd & ~d_hit),
        .st_wbuf  (run & ~i_stall & d_wr & ~wb_empty),
        .st_io    (run & ~i_stall & io_wait),
        .st_struct(1'b0),
        .conflict(conflict), .mem_busy(m_busy),
        .parallel(run & commit & (d_rd | d_wr)),
        .cycles(cycles), .instret(instret),
        .i_reads(i_reads), .i_misses(i_misses), .d_reads(d_reads), .d_misses(d_misses),
        .d_writes(d_writes), .d_write_hits(d_write_hits),
        .c_imiss(c_imiss), .c_dmiss(c_dmiss), .c_wbuf(c_wbuf), .c_io(c_io),
        .c_struct(c_struct), .c_conflict(c_conflict), .c_membusy(c_membusy),
        .c_parallel(c_parallel)
    );
endmodule
