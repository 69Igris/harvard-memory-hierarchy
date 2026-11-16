// ============================================================================
// unified_mem.v  -  Single-ported unified memory (Von Neumann baseline)
// One address port shared by instructions AND data.
//   words [0    .. 1023] : code  (0x0000_0000 - 0x0000_0FFF)
//   words [1024 .. 2047] : data  (0x0000_1000 - 0x0000_1FFF)
// ============================================================================
module unified_mem #(
    parameter DEPTH_WORDS = 2048,                 // 8 KB
    parameter CODE_INIT   = "program.hex",
    parameter DATA_INIT   = ""
)(
    input  wire        clk,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);
    localparam AW = $clog2(DEPTH_WORDS);
    reg [31:0] mem [0:DEPTH_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1)
            mem[i] = (i < DEPTH_WORDS/2) ? 32'h0000_0013 : 32'h0;
        $readmemh(CODE_INIT, mem, 0, DEPTH_WORDS/2 - 1);
        if (DATA_INIT != "") $readmemh(DATA_INIT, mem, DEPTH_WORDS/2, DEPTH_WORDS - 1);
    end

    always @(posedge clk)
        if (we) mem[addr[AW+1:2]] <= wdata;

    assign rdata = mem[addr[AW+1:2]];
endmodule
