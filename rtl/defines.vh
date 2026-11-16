// ============================================================================
// defines.vh  -  Global address map and opcode constants
// Project 9 : Instruction and Data Memory Hierarchy (Harvard vs Von Neumann)
// ============================================================================
`ifndef DEFINES_VH
`define DEFINES_VH

// ---------------------------------------------------------------- Address map
// 0x0000_0000 - 0x0000_0FFF : Instruction memory   (4 KB, 1024 words)
// 0x0000_1000 - 0x0000_1FFF : Data memory          (4 KB, 1024 words)
// 0x0000_2000 - 0x0000_20FF : Memory-mapped I/O    (OUT port, HALT, CYCLE)
`define IMEM_BASE   32'h0000_0000
`define DMEM_BASE   32'h0000_1000
`define IO_BASE     32'h0000_2000

`define IO_OUT      8'h00   // write: debug output port
`define IO_HALT     8'h04   // write: end of simulation ("tohost")
`define IO_CYCLE    8'h08   // read : free-running cycle counter

// ---------------------------------------------------------------- Opcodes
`define OP_RTYPE    7'b0110011
`define OP_ITYPE    7'b0010011
`define OP_LOAD     7'b0000011
`define OP_STORE    7'b0100011
`define OP_BRANCH   7'b1100011
`define OP_JAL      7'b1101111
`define OP_JALR     7'b1100111
`define OP_LUI      7'b0110111

// ---------------------------------------------------------------- ALU ops
`define ALU_ADD     4'd0
`define ALU_SUB     4'd1
`define ALU_AND     4'd2
`define ALU_OR      4'd3
`define ALU_XOR     4'd4
`define ALU_SLT     4'd5
`define ALU_SLL     4'd6
`define ALU_SRL     4'd7
`define ALU_PASSB   4'd8

`endif
