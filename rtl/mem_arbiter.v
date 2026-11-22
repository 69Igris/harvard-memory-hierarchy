// ============================================================================
// mem_arbiter.v  -  2-client arbiter in front of the shared main memory
//
// In the modified-Harvard hierarchy the instruction cache (client I) and the
// data cache (client D) have private, parallel L1 paths, but they SHARE the
// lower-level memory. They only meet here, on a miss or a write-buffer drain.
//
//  * A request is granted when main memory is idle.
//  * Fixed priority: I-side first by default (an I-miss always stalls the
//    core, a write-buffer drain usually does not), selectable with PRIO_I.
//  * The owner of the running transaction is latched so the read beats and
//    the 'done' pulse are routed back to the right cache.
//  * 'conflict' is high in any cycle where BOTH clients are requesting -
//    this is where the shared level re-creates the Von Neumann bottleneck.
// ============================================================================
module mem_arbiter #(
    parameter PRIO_I = 1
)(
    input  wire        clk,
    input  wire        rst,
    // client I (instruction cache)
    input  wire        i_req,
    input  wire        i_we,
    input  wire [31:0] i_addr,
    input  wire [31:0] i_wdata,
    input  wire [4:0]  i_len,
    output wire        i_gnt,
    output wire        i_rvalid,
    output wire        i_done,
    // client D (data cache)
    input  wire        d_req,
    input  wire        d_we,
    input  wire [31:0] d_addr,
    input  wire [31:0] d_wdata,
    input  wire [4:0]  d_len,
    output wire        d_gnt,
    output wire        d_rvalid,
    output wire        d_done,
    // to main memory
    output wire        m_req,
    output wire        m_we,
    output wire [31:0] m_addr,
    output wire [31:0] m_wdata,
    output wire [4:0]  m_len,
    input  wire        m_busy,
    input  wire        m_rvalid,
    input  wire        m_done,
    // status
    output wire        conflict
);
    // ---------------- grant (only when memory is idle)
    wire pick_i = PRIO_I ? i_req : (i_req & ~d_req);
    assign i_gnt = ~m_busy & pick_i;
    assign d_gnt = ~m_busy & d_req & ~pick_i;

    assign m_req   = i_gnt | d_gnt;
    assign m_we    = i_gnt ? i_we    : d_we;
    assign m_addr  = i_gnt ? i_addr  : d_addr;
    assign m_wdata = i_gnt ? i_wdata : d_wdata;
    assign m_len   = i_gnt ? i_len   : d_len;

    // ---------------- remember who owns the bus
    reg owner_i;
    always @(posedge clk) begin
        if (rst)        owner_i <= 1'b0;
        else if (m_req) owner_i <= i_gnt;
    end

    assign i_rvalid = m_rvalid &  owner_i;
    assign i_done   = m_done   &  owner_i;
    assign d_rvalid = m_rvalid & ~owner_i;
    assign d_done   = m_done   & ~owner_i;

    assign conflict = i_req & d_req;
endmodule
