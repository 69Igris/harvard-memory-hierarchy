// ============================================================================
// control_unit.v  -  Main decoder + ALU decoder for the RV32I subset
// Supported: ADD SUB AND OR XOR SLT SLL SRL
//            ADDI ANDI ORI XORI SLTI SLLI SRLI
//            LW SW  BEQ BNE BLT BGE  JAL JALR  LUI
// ============================================================================
`include "defines.vh"

module control_unit (
    input  wire [31:0] instr,
    output reg         reg_write,
    output reg         alu_src_imm,   // 1: ALU B = immediate
    output reg         mem_read,
    output reg         mem_write,
    output reg  [1:0]  wb_sel,        // 0 ALU, 1 MEM, 2 PC+4
    output reg         branch,
    output reg         jal,
    output reg         jalr,
    output reg  [3:0]  alu_op,
    output wire        is_mem,        // load or store -> needs data port
    output reg         illegal
);
    wire [6:0] opcode = instr[6:0];
    wire [2:0] f3     = instr[14:12];
    wire       f7b5   = instr[30];

    always @(*) begin
        reg_write = 0; alu_src_imm = 0; mem_read = 0; mem_write = 0;
        wb_sel = 2'd0; branch = 0; jal = 0; jalr = 0;
        alu_op = `ALU_ADD; illegal = 0;

        case (opcode)
        `OP_RTYPE: begin
            reg_write = 1;
            case (f3)
                3'b000: alu_op = f7b5 ? `ALU_SUB : `ALU_ADD;
                3'b111: alu_op = `ALU_AND;
                3'b110: alu_op = `ALU_OR;
                3'b100: alu_op = `ALU_XOR;
                3'b010: alu_op = `ALU_SLT;
                3'b001: alu_op = `ALU_SLL;
                3'b101: alu_op = `ALU_SRL;
                default: illegal = 1;
            endcase
        end
        `OP_ITYPE: begin
            reg_write = 1; alu_src_imm = 1;
            case (f3)
                3'b000: alu_op = `ALU_ADD;
                3'b111: alu_op = `ALU_AND;
                3'b110: alu_op = `ALU_OR;
                3'b100: alu_op = `ALU_XOR;
                3'b010: alu_op = `ALU_SLT;
                3'b001: alu_op = `ALU_SLL;
                3'b101: alu_op = `ALU_SRL;
                default: illegal = 1;
            endcase
        end
        `OP_LOAD:   begin reg_write = 1; alu_src_imm = 1; mem_read  = 1; wb_sel = 2'd1; end
        `OP_STORE:  begin alu_src_imm = 1; mem_write = 1; end
        `OP_BRANCH: begin branch = 1; alu_op = `ALU_SUB; end
        `OP_JAL:    begin reg_write = 1; jal  = 1; wb_sel = 2'd2; end
        `OP_JALR:   begin reg_write = 1; jalr = 1; alu_src_imm = 1; wb_sel = 2'd2; end
        `OP_LUI:    begin reg_write = 1; alu_src_imm = 1; alu_op = `ALU_PASSB; end
        default:    illegal = (instr != 32'h0);
        endcase
    end

    assign is_mem = (opcode == `OP_LOAD) || (opcode == `OP_STORE);
endmodule
