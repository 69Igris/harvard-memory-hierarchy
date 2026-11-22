// ============================================================================
// hier_perf.v  -  Performance monitor for the Phase II memory hierarchy
//
// Every cycle is either a retire cycle or exactly ONE kind of stall cycle,
// so   cycles == instret + st_imiss + st_dmiss + st_wbuf + st_io + st_struct
// (checked by sim/summarize_hier.py).
// ============================================================================
module hier_perf (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        retire,
    // cache events
    input  wire        ev_i_read, ev_i_miss,
    input  wire        ev_d_read, ev_d_miss, ev_d_write, ev_d_write_hit,
    // stall reasons (mutually exclusive)
    input  wire        st_imiss,           // waiting for an I-line refill
    input  wire        st_dmiss,           // waiting for a D-line refill
    input  wire        st_wbuf,            // store waiting for the write buffer
    input  wire        st_io,              // I/O access waiting for buffer drain
    input  wire        st_struct,          // unified port busy with the other access
    // shared-level activity
    input  wire        conflict,           // I and D both requesting main memory
    input  wire        mem_busy,           // main memory transaction in progress
    input  wire        parallel,           // I-fetch and D-access served in one cycle
    output reg  [31:0] cycles, instret,
    output reg  [31:0] i_reads, i_misses, d_reads, d_misses, d_writes, d_write_hits,
    output reg  [31:0] c_imiss, c_dmiss, c_wbuf, c_io, c_struct,
    output reg  [31:0] c_conflict, c_membusy, c_parallel
);
    always @(posedge clk) begin
        if (rst) begin
            cycles <= 0; instret <= 0;
            i_reads <= 0; i_misses <= 0; d_reads <= 0; d_misses <= 0;
            d_writes <= 0; d_write_hits <= 0;
            c_imiss <= 0; c_dmiss <= 0; c_wbuf <= 0; c_io <= 0; c_struct <= 0;
            c_conflict <= 0; c_membusy <= 0; c_parallel <= 0;
        end else if (enable) begin
            cycles       <= cycles       + 1;
            instret      <= instret      + retire;
            i_reads      <= i_reads      + ev_i_read;
            i_misses     <= i_misses     + ev_i_miss;
            d_reads      <= d_reads      + ev_d_read;
            d_misses     <= d_misses     + ev_d_miss;
            d_writes     <= d_writes     + ev_d_write;
            d_write_hits <= d_write_hits + ev_d_write_hit;
            c_imiss      <= c_imiss      + st_imiss;
            c_dmiss      <= c_dmiss      + st_dmiss;
            c_wbuf       <= c_wbuf       + st_wbuf;
            c_io         <= c_io         + st_io;
            c_struct     <= c_struct     + st_struct;
            c_conflict   <= c_conflict   + conflict;
            c_membusy    <= c_membusy    + mem_busy;
            c_parallel   <= c_parallel   + parallel;
        end
    end
endmodule
