// ============================================================================
// vonneumann_top.v  -  Shared (Von Neumann) memory organisation (BASELINE)
//
// The same cpu_core is connected to ONE single-ported memory. Every
// load/store therefore collides with the next instruction fetch
// (a structural hazard). A 2-state arbiter resolves it:
//
//   FETCH : bus <- PC. If the fetched instruction is a load/store, latch it
//           into IR, assert 'stall', and go to DATA.
//   DATA  : bus <- data address. Core executes the latched IR. Back to FETCH.
//
// => every memory instruction costs 2 cycles instead of 1.
// ============================================================================
`include "defines.vh"

module vonneumann_top #(
    parameter CODE_INIT = "program.hex",
    parameter DATA_INIT = "",
    parameter MEM_WORDS = 2048
)(
    input  wire        clk,
    input  wire        rst,
    output wire        halted,
    output wire [31:0] halt_code,
    output wire [31:0] out_reg,
    output wire        bus_error,
    output wire        illegal
);
    localparam S_FETCH = 1'b0, S_DATA = 1'b1;

    reg         state;
    reg  [31:0] ir;                   // latched instruction for DATA phase

    wire [31:0] i_addr, d_addr, d_wdata, d_rdata_core;
    wire        d_read, d_write, is_mem, retire;
    wire [31:0] bus_rdata;

    // ---------------- arbiter
    wire        in_data   = (state == S_DATA);
    wire [31:0] instr_in  = in_data ? ir : bus_rdata;
    wire        arb_stall = (~in_data & is_mem) | halted;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_FETCH;
            ir    <= 32'h0000_0013;
        end else if (!halted) begin
            case (state)
                S_FETCH: if (is_mem) begin ir <= bus_rdata; state <= S_DATA; end
                S_DATA :             state <= S_FETCH;
            endcase
        end
    end

    // ---------------- core (identical to the Harvard design)
    cpu_core u_core (
        .clk(clk), .rst(rst), .stall(arb_stall),
        .i_addr(i_addr), .i_rdata(instr_in),
        .d_addr(d_addr), .d_wdata(d_wdata), .d_read(d_read), .d_write(d_write),
        .d_rdata(d_rdata_core), .is_mem(is_mem), .retire(retire), .illegal(illegal)
    );

    // ---------------- data-side decode (only meaningful in DATA phase)
    wire sel_imem, sel_dmem, sel_io;
    addr_decoder #(.ALLOW_IMEM_DATA(1)) u_dec (
        .addr(d_addr), .req(in_data & (d_read | d_write)),
        .sel_imem(sel_imem), .sel_dmem(sel_dmem), .sel_io(sel_io),
        .bus_error(bus_error)
    );
    wire sel_mem = sel_imem | sel_dmem;

    wire mem_we, mem_re, io_we, io_re;
    wire [31:0] io_rdata;
    rw_control u_rw (
        .mem_read(d_read), .mem_write(d_write),
        .sel_dmem(sel_mem), .sel_io(sel_io),
        .dmem_rdata(bus_rdata), .io_rdata(io_rdata),
        .dmem_we(mem_we), .dmem_re(mem_re), .io_we(io_we), .io_re(io_re),
        .rdata_to_core(d_rdata_core)
    );

    // ---------------- the single shared bus / memory
    wire [31:0] bus_addr = in_data ? d_addr : i_addr;
    unified_mem #(.DEPTH_WORDS(MEM_WORDS), .CODE_INIT(CODE_INIT), .DATA_INIT(DATA_INIT)) u_mem (
        .clk(clk), .we(mem_we), .addr(bus_addr), .wdata(d_wdata), .rdata(bus_rdata)
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
        .retire(retire), .ifetch(~in_data & ~halted),
        .dread(in_data & d_read), .dwrite(in_data & d_write),
        .stall(arb_stall & ~halted),
        .cycles(cycles), .instret(instret), .n_ifetch(n_ifetch),
        .n_dread(n_dread), .n_dwrite(n_dwrite), .n_stall(n_stall),
        .n_parallel(n_parallel)
    );
endmodule
