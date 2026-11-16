// ============================================================================
// perf_counters.v  -  Access/performance monitor
// Counts cycles, retired instructions, instruction fetches, data reads,
// data writes, stall cycles, and "parallel" cycles in which an instruction
// fetch AND a data access happen in the same clock (only possible with
// split instruction/data paths).
// ============================================================================
module perf_counters (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        retire,
    input  wire        ifetch,
    input  wire        dread,
    input  wire        dwrite,
    input  wire        stall,
    output reg  [31:0] cycles,
    output reg  [31:0] instret,
    output reg  [31:0] n_ifetch,
    output reg  [31:0] n_dread,
    output reg  [31:0] n_dwrite,
    output reg  [31:0] n_stall,
    output reg  [31:0] n_parallel
);
    always @(posedge clk) begin
        if (rst) begin
            cycles <= 0; instret <= 0; n_ifetch <= 0; n_dread <= 0;
            n_dwrite <= 0; n_stall <= 0; n_parallel <= 0;
        end else if (enable) begin
            cycles     <= cycles + 1;
            instret    <= instret    + retire;
            n_ifetch   <= n_ifetch   + ifetch;
            n_dread    <= n_dread    + dread;
            n_dwrite   <= n_dwrite   + dwrite;
            n_stall    <= n_stall    + stall;
            n_parallel <= n_parallel + (ifetch & (dread | dwrite));
        end
    end
endmodule
