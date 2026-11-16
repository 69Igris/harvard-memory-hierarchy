// ============================================================================
// io_regs.v  -  Memory-mapped I/O block
//   +0x00 OUT   (W) : debug output register
//   +0x04 HALT  (W) : any write stops the simulation / raises 'halted'
//   +0x08 CYCLE (R) : free-running cycle counter
// ============================================================================
`include "defines.vh"

module io_regs (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,
    input  wire        re,
    input  wire [7:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output reg  [31:0] out_reg,
    output reg         halted,
    output reg  [31:0] halt_code
);
    reg [31:0] cycle_cnt;

    always @(posedge clk) begin
        if (rst) begin
            cycle_cnt <= 0;
            out_reg   <= 0;
            halted    <= 0;
            halt_code <= 0;
        end else begin
            cycle_cnt <= cycle_cnt + 1;
            if (we && addr == `IO_OUT)  out_reg <= wdata;
            if (we && addr == `IO_HALT) begin
                halted    <= 1'b1;
                halt_code <= wdata;
            end
        end
    end

    always @(*) begin
        rdata = 32'h0;
        if (re && addr == `IO_CYCLE) rdata = cycle_cnt;
        if (re && addr == `IO_OUT)   rdata = out_reg;
    end
endmodule
