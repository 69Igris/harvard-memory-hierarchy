// ============================================================================
// tb_hier.v  -  Self-checking testbench for the Phase II memory HIERARCHY
//
// Compile with  -DMODHARVARD -> modharvard_top (split L1 I$/D$ + shared memory)
//          or   -DUNICACHE   -> unicache_top   (unified L1 + shared memory)
//
// Parameters (override with iverilog -P):
//   PROG, DATA, EXPECT, NAME, VCD   as in tb_top.v (VCD = "" -> no dump)
//   CFG        label printed in the PERF line
//   LAT        main-memory latency          SETS   L1 lines (per cache)
//   LINE       words per line               NOCACHE 1 = flat (no L1)
//
// At HALT the testbench
//   1. checks that the write buffer is empty (HALT acts as a fence),
//   2. compares the data half of main memory with the golden image,
//   3. prints a PERF line with every hierarchy counter.
// ============================================================================
`timescale 1ns/1ps

module tb_hier;
    parameter PROG    = "program.hex";
    parameter DATA    = "";
    parameter EXPECT  = "expect.hex";
    parameter NAME    = "program";
    parameter VCD     = "";
    parameter CFG     = "cfg";
    parameter LAT     = 4;
    parameter SETS    = 16;
    parameter LINE    = 4;
    parameter NOCACHE = 0;
    parameter MAX_CYCLES = 400000;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    wire        halted, bus_error, illegal;
    wire [31:0] halt_code, out_reg;

`ifdef UNICACHE
    localparam ARCH = "unified";
    unicache_top #(.CODE_INIT(PROG), .DATA_INIT(DATA), .LAT(LAT), .U_SETS(SETS),
                   .LINE_WORDS(LINE), .NOCACHE(NOCACHE)) dut (
        .clk(clk), .rst(rst), .halted(halted), .halt_code(halt_code),
        .out_reg(out_reg), .bus_error(bus_error), .illegal(illegal));
    wire wb_empty = dut.u_cache.wb_empty;
`else
    localparam ARCH = "split";
    modharvard_top #(.CODE_INIT(PROG), .DATA_INIT(DATA), .LAT(LAT), .I_SETS(SETS),
                     .D_SETS(SETS), .LINE_WORDS(LINE), .NOCACHE(NOCACHE)) dut (
        .clk(clk), .rst(rst), .halted(halted), .halt_code(halt_code),
        .out_reg(out_reg), .bus_error(bus_error), .illegal(illegal));
    wire wb_empty = dut.u_dcache.wb_empty;
`endif

    reg [31:0] expect_mem [0:1023];
    integer i, errors, cyc, warn;

    initial begin
        if (VCD != "") begin
            $dumpfile(VCD);
            $dumpvars(0, tb_hier);
        end
        $readmemh(EXPECT, expect_mem);

        repeat (2) @(posedge clk);
        #1 rst = 0;

        cyc = 0; warn = 0;
        while (!halted && cyc < MAX_CYCLES) begin
            @(posedge clk); #1;
            cyc = cyc + 1;
            if (bus_error && !dut.core_stall) begin
                warn = warn + 1;
                $display("[%0t] WARNING: bus error, addr=%h", $time, dut.u_core.d_addr);
            end
            if (illegal) begin
                warn = warn + 1;
                $display("[%0t] WARNING: illegal instruction", $time);
            end
        end

        if (!halted) begin
            $display("FAIL %s/%s/%s : timeout after %0d cycles", ARCH, CFG, NAME, cyc);
            $finish;
        end

        errors = 0;
        if (!wb_empty) begin
            $display("  write buffer not empty at HALT");
            errors = errors + 1;
        end
        for (i = 0; i < 1024; i = i + 1) begin
            if (dut.u_mem.mem[1024 + i] !== expect_mem[i]) begin
                if (errors < 10)
                    $display("  mismatch mem[%0d] (addr %h): got %h expected %h",
                             i, 32'h1000 + 4*i, dut.u_mem.mem[1024 + i], expect_mem[i]);
                errors = errors + 1;
            end
        end
        errors = errors + warn;

        $display("PERF arch=%s cfg=%s prog=%s lat=%0d sets=%0d line=%0d nocache=%0d cycles=%0d instret=%0d i_reads=%0d i_misses=%0d d_reads=%0d d_misses=%0d d_writes=%0d d_write_hits=%0d st_imiss=%0d st_dmiss=%0d st_wbuf=%0d st_io=%0d st_struct=%0d conflict=%0d membusy=%0d parallel=%0d out=%0d errors=%0d",
                 ARCH, CFG, NAME, LAT, SETS, LINE, NOCACHE,
                 dut.u_perf.cycles, dut.u_perf.instret,
                 dut.u_perf.i_reads, dut.u_perf.i_misses,
                 dut.u_perf.d_reads, dut.u_perf.d_misses,
                 dut.u_perf.d_writes, dut.u_perf.d_write_hits,
                 dut.u_perf.c_imiss, dut.u_perf.c_dmiss, dut.u_perf.c_wbuf,
                 dut.u_perf.c_io, dut.u_perf.c_struct,
                 dut.u_perf.c_conflict, dut.u_perf.c_membusy, dut.u_perf.c_parallel,
                 $signed(out_reg), errors);
        if (errors == 0) $display("PASS %s/%s/%s", ARCH, CFG, NAME);
        else             $display("FAIL %s/%s/%s : %0d errors", ARCH, CFG, NAME, errors);
        repeat (3) @(posedge clk);
        $finish;
    end
endmodule
