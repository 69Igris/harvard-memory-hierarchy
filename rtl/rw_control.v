// ============================================================================
// rw_control.v  -  Read/Write Control Unit
// Combines the core's load/store request with the decoder's chip selects:
//   * routes write-enable / read-enable only to the selected device
//   * multiplexes the selected device's read data back to the core
// ============================================================================
module rw_control (
    input  wire        mem_read,      // from core (load)
    input  wire        mem_write,     // from core (store)
    input  wire        sel_dmem,
    input  wire        sel_io,
    input  wire [31:0] dmem_rdata,
    input  wire [31:0] io_rdata,
    output wire        dmem_we,
    output wire        dmem_re,
    output wire        io_we,
    output wire        io_re,
    output wire [31:0] rdata_to_core
);
    assign dmem_we = mem_write & sel_dmem;
    assign dmem_re = mem_read  & sel_dmem;
    assign io_we   = mem_write & sel_io;
    assign io_re   = mem_read  & sel_io;

    assign rdata_to_core = sel_dmem ? dmem_rdata :
                           sel_io   ? io_rdata   : 32'h0;
endmodule
