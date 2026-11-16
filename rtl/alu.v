// ============================================================================
// alu.v  -  32-bit ALU
// ============================================================================
`include "defines.vh"

module alu (
    input  wire [3:0]  op,
    input  wire [31:0] a, b,
    output reg  [31:0] y,
    output wire        zero,
    output wire        lt              // signed a < b (for BLT/BGE)
);
    assign lt   = ($signed(a) < $signed(b));
    assign zero = (a == b);

    always @(*) begin
        case (op)
            `ALU_ADD:   y = a + b;
            `ALU_SUB:   y = a - b;
            `ALU_AND:   y = a & b;
            `ALU_OR:    y = a | b;
            `ALU_XOR:   y = a ^ b;
            `ALU_SLT:   y = {31'b0, lt};
            `ALU_SLL:   y = a << b[4:0];
            `ALU_SRL:   y = a >> b[4:0];
            `ALU_PASSB: y = b;
            default:    y = 32'h0;
        endcase
    end
endmodule
