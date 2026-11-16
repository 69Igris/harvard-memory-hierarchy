// ============================================================================
// cpu_core.v  -  Single-cycle RV32I-subset core with SEPARATE
//                instruction-port and data-port interfaces.
//
// The core itself is memory-organisation agnostic: it exposes an
// instruction port (pc -> instr) and a data port (addr/wdata/rd/wr -> rdata).
//   * harvard_top     connects the two ports to two independent memories.
//   * vonneumann_top  funnels both ports into ONE single-ported memory via
//                     an arbiter that asserts 'stall' on structural conflicts.
// ============================================================================
`include "defines.vh"

module cpu_core (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,          // freeze PC + architectural writes

    // ---------------- instruction port
    output wire [31:0] i_addr,
    input  wire [31:0] i_rdata,

    // ---------------- data port
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,
    output wire        d_read,
    output wire        d_write,
    input  wire [31:0] d_rdata,

    // ---------------- status
    output wire        is_mem,         // current instr needs the data port
    output wire        retire,         // instruction completes this cycle
    output wire        illegal
);
    // ---------------------------------------------------------------- fetch
    wire [31:0] pc_q, pc_next;
    pc u_pc (.clk(clk), .rst(rst), .stall(stall), .pc_next(pc_next), .pc_q(pc_q));
    assign i_addr = pc_q;
    wire [31:0] instr = i_rdata;

    // ---------------------------------------------------------------- decode
    wire       reg_write, alu_src_imm, mem_read, mem_write, branch, jal, jalr;
    wire [1:0] wb_sel;
    wire [3:0] alu_op;
    control_unit u_ctrl (
        .instr(instr), .reg_write(reg_write), .alu_src_imm(alu_src_imm),
        .mem_read(mem_read), .mem_write(mem_write), .wb_sel(wb_sel),
        .branch(branch), .jal(jal), .jalr(jalr), .alu_op(alu_op),
        .is_mem(is_mem), .illegal(illegal)
    );

    wire [4:0]  rs1 = instr[19:15], rs2 = instr[24:20], rd = instr[11:7];
    wire [31:0] rd1, rd2, wb_data, imm;
    regfile u_rf (
        .clk(clk), .we(reg_write & ~stall & ~rst),
        .rs1(rs1), .rs2(rs2), .rd(rd), .wd(wb_data), .rd1(rd1), .rd2(rd2)
    );
    imm_gen u_imm (.instr(instr), .imm(imm));

    // ---------------------------------------------------------------- execute
    wire [31:0] alu_y;
    wire        zero, lt;
    alu u_alu (.op(alu_op), .a(rd1), .b(alu_src_imm ? imm : rd2),
               .y(alu_y), .zero(zero), .lt(lt));

    // branch resolution
    reg take;
    always @(*) begin
        case (instr[14:12])
            3'b000:  take = zero;   // BEQ
            3'b001:  take = ~zero;  // BNE
            3'b100:  take = lt;     // BLT
            3'b101:  take = ~lt;    // BGE
            default: take = 1'b0;
        endcase
    end

    wire [31:0] pc_plus4  = pc_q + 32'd4;
    wire [31:0] pc_target = pc_q + imm;
    assign pc_next = jal                ? pc_target :
                     jalr               ? ((rd1 + imm) & ~32'd1) :
                     (branch && take)   ? pc_target : pc_plus4;

    // ---------------------------------------------------------------- memory
    assign d_addr  = alu_y;
    assign d_wdata = rd2;
    assign d_read  = mem_read;
    assign d_write = mem_write & ~stall & ~rst;

    // ---------------------------------------------------------------- write-back
    assign wb_data = (wb_sel == 2'd1) ? d_rdata  :
                     (wb_sel == 2'd2) ? pc_plus4 : alu_y;

    assign retire = ~stall & ~rst;
endmodule
