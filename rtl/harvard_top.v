// ============================================================================
// harvard_top.v  -  Harvard memory organisation (PROPOSED DESIGN)
//
//            +-----------+   i_addr / i_rdata   +-------------+
//            |           |<-------------------->|    IMEM     |  (4 KB ROM)
//            |           |                      +-------------+
//            | cpu_core  |   d_addr/d_wdata     +-------------+   +------+
//            |           |--------------------->| addr_decoder|-->| DMEM |
//            |           |<---- rw_control -----|             |-->| I/O  |
//            +-----------+                      +-------------+   +------+
//
// Instruction fetch and data access use physically separate buses, so a
// load/store and the next instruction fetch happen in the SAME cycle.
// ============================================================================
`include "defines.vh"

module harvard_top #(
    parameter IMEM_INIT = "program.hex",
    parameter DMEM_INIT = "",
    parameter IMEM_WORDS = 1024,
    parameter DMEM_WORDS = 1024
)(
    input  wire        clk,
    input  wire        rst,
    output wire        halted,
    output wire [31:0] halt_code,
    output wire [31:0] out_reg,
    output wire        bus_error,
    output wire        illegal
);
    // ---------------- core
    wire [31:0] i_addr, i_rdata, d_addr, d_wdata, d_rdata;
    wire        d_read, d_write, is_mem, retire;

    cpu_core u_core (
        .clk(clk), .rst(rst), .stall(halted),
        .i_addr(i_addr), .i_rdata(i_rdata),
        .d_addr(d_addr), .d_wdata(d_wdata), .d_read(d_read), .d_write(d_write),
        .d_rdata(d_rdata), .is_mem(is_mem), .retire(retire), .illegal(illegal)
    );

    // ---------------- instruction side
    wire i_access;
    imem #(.DEPTH_WORDS(IMEM_WORDS), .INIT_FILE(IMEM_INIT)) u_imem (
        .addr(i_addr), .rdata(i_rdata), .access(i_access)
    );

    // ---------------- data side
    wire sel_imem, sel_dmem, sel_io;
    addr_decoder #(.ALLOW_IMEM_DATA(0)) u_dec (
        .addr(d_addr), .req(d_read | d_write),
        .sel_imem(sel_imem), .sel_dmem(sel_dmem), .sel_io(sel_io),
        .bus_error(bus_error)
    );

    wire dmem_we, dmem_re, io_we, io_re;
    wire [31:0] dmem_rdata, io_rdata;
    rw_control u_rw (
        .mem_read(d_read), .mem_write(d_write),
        .sel_dmem(sel_dmem), .sel_io(sel_io),
        .dmem_rdata(dmem_rdata), .io_rdata(io_rdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re), .io_we(io_we), .io_re(io_re),
        .rdata_to_core(d_rdata)
    );

    dmem #(.DEPTH_WORDS(DMEM_WORDS), .INIT_FILE(DMEM_INIT)) u_dmem (
        .clk(clk), .cs(sel_dmem), .we(dmem_we), .re(dmem_re),
        .addr(d_addr - `DMEM_BASE), .wdata(d_wdata), .rdata(dmem_rdata)
    );

    io_regs u_io (
        .clk(clk), .rst(rst), .we(io_we), .re(io_re), .addr(d_addr[7:0]),
        .wdata(d_wdata), .rdata(io_rdata), .out_reg(out_reg),
        .halted(halted), .halt_code(halt_code)
    );

    // ---------------- performance monitor
    wire [31:0] cycles, instret, n_ifetch, n_dread, n_dwrite, n_stall, n_parallel;
    perf_counters u_perf (
        .clk(clk), .rst(rst), .enable(~halted),
        .retire(retire), .ifetch(i_access & ~halted),
        .dread(d_read & ~halted), .dwrite(d_write),
        .stall(1'b0),
        .cycles(cycles), .instret(instret), .n_ifetch(n_ifetch),
        .n_dread(n_dread), .n_dwrite(n_dwrite), .n_stall(n_stall),
        .n_parallel(n_parallel)
    );
endmodule
