// ============================================================================
// imem.v  -  Instruction Memory (Harvard side, read-only)
// Word-organised ROM, loaded from a hex file at elaboration time.
// Asynchronous (combinational) read so a single-cycle core can fetch and
// execute in the same clock period.
// ============================================================================
module imem #(
    parameter DEPTH_WORDS = 1024,                // 4 KB
    parameter INIT_FILE   = "program.hex"
)(
    input  wire [31:0] addr,                     // byte address from PC
    output wire [31:0] rdata,
    output wire        access                    // high when a fetch occurs
);
    localparam AW = $clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) mem[i] = 32'h0000_0013; // NOP
        $readmemh(INIT_FILE, mem);
    end

    assign rdata  = mem[addr[AW+1:2]];           // word aligned
    assign access = 1'b1;                        // fetch every cycle
endmodule
