// ============================================================================
// tb_l1_cache.v  -  Directed unit test: l1_cache + main_mem timing/behaviour
//
// Geometry: 4 sets x 4 words (64 B), main-memory latency LAT = 4.
// Checks (each prints PASS/FAIL):
//   1. cold read miss stalls exactly LAT + LINE_WORDS cycles, then returns data
//   2. another word of the same line hits with zero stall (spatial locality)
//   3. store hit completes in 1 cycle and updates the cached copy
//   4. a 2nd back-to-back store waits LAT + 1 cycles for the write buffer
//   5. conflicting address (same index, different tag) evicts the line
//   6. a load to a line whose store is still buffered waits for the drain
//      (no stale read)  -> read-after-write safe
//   7. after draining, main memory holds every stored value (write-through)
// ============================================================================
`timescale 1ns/1ps
module tb_l1_cache;
    localparam LAT = 4, SETS = 4, LW = 4;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg         rd = 0, wr = 0;
    reg  [31:0] addr = 0, wdata = 0;
    wire [31:0] rdata;
    wire        stall, hit, wb_empty;
    wire        commit = (rd | wr) & ~stall;

    wire        m_req, m_we, m_busy, m_rvalid, m_done;
    wire [31:0] m_addr, m_wdata, m_rdata;
    wire [4:0]  m_len;
    wire        m_gnt = m_req & ~m_busy;

    l1_cache #(.SETS(SETS), .LINE_WORDS(LW), .WRITABLE(1)) dut (
        .clk(clk), .rst(rst), .rd(rd), .wr(wr), .commit(commit), .addr(addr),
        .wdata(wdata), .rdata(rdata), .stall(stall), .hit(hit), .wb_empty(wb_empty),
        .mreq(m_req), .mwe(m_we), .maddr(m_addr), .mwdata(m_wdata), .mlen(m_len),
        .mgnt(m_gnt), .mrvalid(m_rvalid), .mdone(m_done), .mrdata(m_rdata),
        .refilling(), .draining(), .ev_read(), .ev_read_miss(), .ev_write(), .ev_write_hit());

    main_mem #(.LAT(LAT), .CODE_INIT(""), .DATA_INIT("")) u_mem (
        .clk(clk), .rst(rst), .req(m_gnt), .we(m_we), .addr(m_addr), .wdata(m_wdata),
        .len(m_len), .busy(m_busy), .rvalid(m_rvalid), .rdata(m_rdata), .done(m_done));

    integer errors = 0, tests = 0, st;
    reg [31:0] got;

    task check(input [639:0] what, input ok);
        begin
            tests = tests + 1;
            if (!ok) begin errors = errors + 1; $display("FAIL %0s", what); end
            else            $display("  ok  %0s", what);
        end
    endtask

    // one access; returns number of stall cycles in 'st' and read data in 'got'
    task access(input is_wr, input [31:0] a, input [31:0] d);
        begin
            @(negedge clk);
            rd = ~is_wr; wr = is_wr; addr = a; wdata = d; st = 0;
            #1;
            while (stall) begin @(negedge clk); st = st + 1; #1; end
            got = rdata;
            @(posedge clk); #1;
            rd = 0; wr = 0;
        end
    endtask

    task drain;
        begin
            while (!wb_empty) @(posedge clk);
            #1;
        end
    endtask

    integer i;
    initial begin
        #1;   // let main_mem's own initial block run first, then preload data
        for (i = 0; i < 1024; i = i + 1) u_mem.mem[1024 + i] = 32'hA000_0000 + i;
        repeat (2) @(posedge clk); #1 rst = 0;

        access(0, 32'h1000, 0);
        check("1 cold read miss: stall = LAT + LINE_WORDS", st == LAT + LW);
        check("1 cold read miss: correct data", got == 32'hA000_0000);

        access(0, 32'h100C, 0);
        check("2 same-line read hits with 0 stall", st == 0 && got == 32'hA000_0003);

        access(1, 32'h1004, 32'h1111_1111);
        check("3 store hit completes in 1 cycle", st == 0);
        access(0, 32'h1004, 0);
        check("3 cached copy updated by store", st == 0 && got == 32'h1111_1111);

        drain;
        access(1, 32'h1008, 32'h2222_2222);
        access(1, 32'h100C, 32'h3333_3333);
        check("4 back-to-back store waits LAT+1 for write buffer", st == LAT + 1);

        drain;
        access(0, 32'h1040, 0);          // same index as 0x1000 (4 sets x 16 B)
        check("5 conflicting line misses", st == LAT + LW && got == 32'hA000_0010);
        access(0, 32'h1000, 0);
        check("5 original line was evicted (misses again)", st == LAT + LW);

        access(1, 32'h1080, 32'h4444_4444);   // store miss (no allocate), buffered
        access(0, 32'h1080, 0);               // load the same word immediately
        check("6 load after buffered store returns NEW value", got == 32'h4444_4444);
        check("6 ... after waiting for drain + refill", st > LAT + LW);

        drain;
        check("7 write-through: memory holds stored values",
              u_mem.mem[1024 + 1] == 32'h1111_1111 && u_mem.mem[1024 + 2] == 32'h2222_2222 &&
              u_mem.mem[1024 + 3] == 32'h3333_3333 && u_mem.mem[1024 + 32] == 32'h4444_4444);

        if (errors == 0) $display("PASS l1_cache/main_mem : %0d directed checks", tests);
        else             $display("FAIL l1_cache/main_mem : %0d of %0d checks failed", errors, tests);
        $finish;
    end
endmodule
