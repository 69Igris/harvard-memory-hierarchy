// ============================================================================
// addr_decoder.v  -  Data-side Address Decoder
// Decodes the upper address bits of a load/store into one-hot chip selects:
//   0x0000_1xxx -> Data memory
//   0x0000_20xx -> Memory-mapped I/O
//   0x0000_0xxx -> Instruction region (illegal for data in Harvard mode,
//                  legal in the unified/Von Neumann memory)
//   anything else -> bus error
// ============================================================================
`include "defines.vh"

module addr_decoder #(
    parameter ALLOW_IMEM_DATA = 0     // 1 = unified memory (Von Neumann)
)(
    input  wire [31:0] addr,
    input  wire        req,           // a data access is requested
    output wire        sel_imem,
    output wire        sel_dmem,
    output wire        sel_io,
    output wire        bus_error
);
    wire in_imem = (addr[31:12] == 20'h00000);
    wire in_dmem = (addr[31:12] == 20'h00001);
    wire in_io   = (addr[31:8]  == 24'h000020);

    assign sel_imem  = req & in_imem & (ALLOW_IMEM_DATA != 0);
    assign sel_dmem  = req & in_dmem;
    assign sel_io    = req & in_io;
    assign bus_error = req & ~(sel_imem | sel_dmem | sel_io);
endmodule
