// ============================================================================
// tb_top.v  -  Self-checking testbench for BOTH memory organisations
//
// Compile with  -DHARVARD   -> instantiates harvard_top
//          or   -DVONNEUMANN -> instantiates vonneumann_top
//
// Parameters (override with iverilog -P):
//   PROG   : instruction image  (.hex)
//   DATA   : initial data image (.hex)
//   EXPECT : expected final data-memory image produced by the Python ISS
//   NAME   : program name (for the log)
//   VCD    : waveform output file
//
// The TB runs until the program writes the I/O HALT register, then
//   1. compares all 1024 data-memory words with EXPECT,
//   2. prints a machine-readable PERF line with the hardware counters.
// ============================================================================
`timescale 1ns/1ps

module tb_top;
    parameter PROG   = "program.hex";
    parameter DATA   = "";
    parameter EXPECT = "expect.hex";
    parameter NAME   = "program";
    parameter VCD    = "wave.vcd";
    parameter MAX_CYCLES = 100000;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;                  // 100 MHz simulation clock

    wire        halted, bus_error, illegal;
    wire [31:0] halt_code, out_reg;

`ifdef VONNEUMANN
    localparam ARCH = "vonneumann";
    vonneumann_top #(.CODE_INIT(PROG), .DATA_INIT(DATA)) dut (
        .clk(clk), .rst(rst), .halted(halted), .halt_code(halt_code),
        .out_reg(out_reg), .bus_error(bus_error), .illegal(illegal));
    `define DMEM_WORD(i) dut.u_mem.mem[1024 + (i)]
`else
    localparam ARCH = "harvard";
    harvard_top #(.IMEM_INIT(PROG), .DMEM_INIT(DATA)) dut (
        .clk(clk), .rst(rst), .halted(halted), .halt_code(halt_code),
        .out_reg(out_reg), .bus_error(bus_error), .illegal(illegal));
    `define DMEM_WORD(i) dut.u_dmem.mem[(i)]
`endif

    reg [31:0] expect_mem [0:1023];
    integer i, errors, cyc;

    initial begin
        $dumpfile(VCD);
        $dumpvars(0, tb_top);
        $readmemh(EXPECT, expect_mem);

        repeat (2) @(posedge clk);
        #1 rst = 0;

        cyc = 0;
        while (!halted && cyc < MAX_CYCLES) begin
            @(posedge clk); #1;
            cyc = cyc + 1;
            if (bus_error) $display("[%0t] WARNING: bus error, addr=%h", $time, dut.u_core.d_addr);
            if (illegal)   $display("[%0t] WARNING: illegal instruction %h", $time, dut.u_core.i_rdata);
        end

        if (!halted) begin
            $display("FAIL %s/%s : timeout after %0d cycles", ARCH, NAME, cyc);
            $finish;
        end

        // ---------------- check data memory against golden model
        errors = 0;
        for (i = 0; i < 1024; i = i + 1) begin
            if (`DMEM_WORD(i) !== expect_mem[i]) begin
                if (errors < 10)
                    $display("  mismatch dmem[%0d] (addr %h): got %h expected %h",
                             i, 32'h1000 + 4*i, `DMEM_WORD(i), expect_mem[i]);
                errors = errors + 1;
            end
        end

        $display("PERF arch=%s prog=%s cycles=%0d instret=%0d ifetch=%0d dread=%0d dwrite=%0d stall=%0d parallel=%0d out=%0d errors=%0d",
                 ARCH, NAME, dut.u_perf.cycles, dut.u_perf.instret, dut.u_perf.n_ifetch,
                 dut.u_perf.n_dread, dut.u_perf.n_dwrite, dut.u_perf.n_stall,
                 dut.u_perf.n_parallel, $signed(out_reg), errors);
        if (errors == 0) $display("PASS %s/%s", ARCH, NAME);
        else             $display("FAIL %s/%s : %0d data-memory mismatches", ARCH, NAME, errors);
        repeat (3) @(posedge clk);
        $finish;
    end
endmodule
