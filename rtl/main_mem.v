// ============================================================================
// main_mem.v  -  Shared lower-level (main) memory with configurable latency
// Phase II: the "Optional Shared Lower-Level Memory" of Project 9.
//
// One single-ported 8 KB memory that holds BOTH code and data (same layout as
// unified_mem.v), but it is now SLOW: every transaction takes LAT cycles
// before the first word is available. Reads may be bursts of LEN words
// (a whole cache line); after the first word, one word arrives per cycle.
//
//   words [0    .. 1023] : code  (0x0000_0000 - 0x0000_0FFF)
//   words [1024 .. 2047] : data  (0x0000_1000 - 0x0000_1FFF)
//
// Handshake (driven by mem_arbiter.v):
//   cycle t        : req=1 while busy=0  -> transaction accepted
//   cycle t+LAT    : first read beat (rvalid=1) / write performed (done=1)
//   cycle t+LAT+k  : read beat k (k < len); done=1 on the last beat
//   cycle after done: busy=0, next request may be accepted
// ============================================================================
module main_mem #(
    parameter DEPTH_WORDS = 2048,
    parameter LAT         = 4,             // first-word latency (>= 1)
    parameter CODE_INIT   = "program.hex",
    parameter DATA_INIT   = ""
)(
    input  wire        clk,
    input  wire        rst,
    // request
    input  wire        req,
    input  wire        we,
    input  wire [31:0] addr,               // byte address of first word
    input  wire [31:0] wdata,
    input  wire [4:0]  len,                // words in burst (1..16)
    // response
    output wire        busy,
    output wire        rvalid,             // a read word is on rdata
    output wire [31:0] rdata,
    output wire        done                // last beat / write complete
);
    localparam AW = $clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1)
            mem[i] = (i < DEPTH_WORDS/2) ? 32'h0000_0013 : 32'h0;
        if (CODE_INIT != "") $readmemh(CODE_INIT, mem, 0, DEPTH_WORDS/2 - 1);
        if (DATA_INIT != "") $readmemh(DATA_INIT, mem, DEPTH_WORDS/2, DEPTH_WORDS - 1);
    end

    reg          active;
    reg          t_we;
    reg [AW-1:0] t_word;
    reg [31:0]   t_wdata;
    reg [4:0]    t_len;
    reg [4:0]    beat;
    reg [7:0]    cnt;                       // cycles left until a beat

    wire beat_now = active && (cnt == 8'd1);
    wire [AW-1:0] cur_word = t_word + beat;

    assign busy   = active;
    assign rvalid = beat_now & ~t_we;
    assign rdata  = mem[cur_word];
    assign done   = beat_now & (t_we | (beat == t_len - 5'd1));

    always @(posedge clk) begin
        if (rst) begin
            active <= 1'b0;
            beat   <= 0;
            cnt    <= 0;
        end else if (!active) begin
            if (req) begin
                active  <= 1'b1;
                t_we    <= we;
                t_word  <= addr[AW+1:2];
                t_wdata <= wdata;
                t_len   <= (len == 0) ? 5'd1 : len;
                beat    <= 0;
                cnt     <= LAT[7:0];
            end
        end else begin
            if (cnt > 8'd1) begin
                cnt <= cnt - 8'd1;
            end else begin                  // beat cycle
                if (t_we) mem[t_word] <= t_wdata;
                if (done) active <= 1'b0;
                else      beat   <= beat + 5'd1;
            end
        end
    end
endmodule
