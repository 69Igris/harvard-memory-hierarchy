// ============================================================================
// dmem.v  -  Data Memory (Harvard side, read/write)
// Word-organised RAM with synchronous write and asynchronous read.
// The chip-select (cs) comes from the address decoder; we/re come from the
// read/write control unit.
// ============================================================================
module dmem #(
    parameter DEPTH_WORDS = 1024,                // 4 KB
    parameter INIT_FILE   = ""
)(
    input  wire        clk,
    input  wire        cs,                       // chip select (decoder)
    input  wire        we,                       // write enable
    input  wire        re,                       // read enable
    input  wire [31:0] addr,                     // byte address
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);
    localparam AW = $clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];
    wire [AW-1:0] widx = addr[AW+1:2];

    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) mem[i] = 32'h0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk)
        if (cs && we) mem[widx] <= wdata;

    assign rdata = (cs && re) ? mem[widx] : 32'h0;
endmodule
