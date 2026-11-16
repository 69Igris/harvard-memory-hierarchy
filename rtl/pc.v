// ============================================================================
// pc.v  -  Program Counter
// Holds the address of the instruction currently being fetched.
// 'stall' freezes the PC (used by the Von Neumann arbiter when the single
// memory port is busy serving a data access).
// ============================================================================
module pc #(
    parameter RESET_ADDR = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire [31:0] pc_next,
    output reg  [31:0] pc_q
);
    always @(posedge clk) begin
        if (rst)         pc_q <= RESET_ADDR;
        else if (!stall) pc_q <= pc_next;
    end
endmodule
