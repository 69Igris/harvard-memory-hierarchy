// ============================================================================
// regfile.v  -  32 x 32-bit register file (x0 hard-wired to zero)
// Two asynchronous read ports, one synchronous write port.
// ============================================================================
module regfile (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  rs1, rs2, rd,
    input  wire [31:0] wd,
    output wire [31:0] rd1, rd2
);
    reg [31:0] r [0:31];
    integer i;
    initial for (i = 0; i < 32; i = i + 1) r[i] = 32'h0;

    always @(posedge clk)
        if (we && rd != 5'd0) r[rd] <= wd;

    assign rd1 = (rs1 == 5'd0) ? 32'h0 : r[rs1];
    assign rd2 = (rs2 == 5'd0) ? 32'h0 : r[rs2];
endmodule
