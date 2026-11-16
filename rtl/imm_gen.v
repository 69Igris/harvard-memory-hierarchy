// ============================================================================
// imm_gen.v  -  RV32I immediate generator (I, S, B, U, J formats)
// ============================================================================
`include "defines.vh"

module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    wire [6:0] opcode = instr[6:0];
    always @(*) begin
        case (opcode)
            `OP_ITYPE, `OP_LOAD, `OP_JALR:
                imm = {{20{instr[31]}}, instr[31:20]};
            `OP_STORE:
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            `OP_BRANCH:
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            `OP_LUI:
                imm = {instr[31:12], 12'b0};
            `OP_JAL:
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default:
                imm = 32'h0;
        endcase
    end
endmodule
