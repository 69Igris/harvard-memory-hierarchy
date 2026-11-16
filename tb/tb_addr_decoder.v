// ============================================================================
// tb_addr_decoder.v  -  Directed unit test for addr_decoder + rw_control
// Checks chip-select generation for every region of the address map and
// that read/write enables are routed only to the selected device.
// ============================================================================
`timescale 1ns/1ps

module tb_addr_decoder;
    reg  [31:0] addr;
    reg         rd, wr;
    wire        h_imem, h_dmem, h_io, h_err;   // Harvard decoder
    wire        v_imem, v_dmem, v_io, v_err;   // unified decoder
    wire        dmem_we, dmem_re, io_we, io_re;
    wire [31:0] rdata;

    addr_decoder #(.ALLOW_IMEM_DATA(0)) dec_h (.addr(addr), .req(rd|wr),
        .sel_imem(h_imem), .sel_dmem(h_dmem), .sel_io(h_io), .bus_error(h_err));
    addr_decoder #(.ALLOW_IMEM_DATA(1)) dec_v (.addr(addr), .req(rd|wr),
        .sel_imem(v_imem), .sel_dmem(v_dmem), .sel_io(v_io), .bus_error(v_err));
    rw_control rwc (.mem_read(rd), .mem_write(wr), .sel_dmem(h_dmem), .sel_io(h_io),
        .dmem_rdata(32'hDDDD_DDDD), .io_rdata(32'h1111_1111),
        .dmem_we(dmem_we), .dmem_re(dmem_re), .io_we(io_we), .io_re(io_re),
        .rdata_to_core(rdata));

    integer errors = 0, tests = 0;

    task check(input [31:0] a, input r, input w,
               input [3:0] exp_h,        // {imem,dmem,io,err} Harvard
               input [3:0] exp_v,        // {imem,dmem,io,err} unified
               input [3:0] exp_en,       // {dmem_we,dmem_re,io_we,io_re}
               input [31:0] exp_rd);
        begin
            addr = a; rd = r; wr = w; #1;
            tests = tests + 1;
            if ({h_imem,h_dmem,h_io,h_err} !== exp_h ||
                {v_imem,v_dmem,v_io,v_err} !== exp_v ||
                {dmem_we,dmem_re,io_we,io_re} !== exp_en ||
                rdata !== exp_rd) begin
                errors = errors + 1;
                $display("  FAIL addr=%h rd=%b wr=%b : H=%b V=%b EN=%b RD=%h",
                    a, r, w, {h_imem,h_dmem,h_io,h_err}, {v_imem,v_dmem,v_io,v_err},
                    {dmem_we,dmem_re,io_we,io_re}, rdata);
            end
        end
    endtask

    initial begin
        //            addr          rd wr   Harvard  Unified  enables  read data
        check(32'h0000_1000, 1, 0, 4'b0100, 4'b0100, 4'b0100, 32'hDDDD_DDDD); // DMEM load
        check(32'h0000_1FFC, 0, 1, 4'b0100, 4'b0100, 4'b1000, 32'hDDDD_DDDD); // DMEM store (top)
        check(32'h0000_2000, 0, 1, 4'b0010, 4'b0010, 4'b0010, 32'h1111_1111); // IO OUT write
        check(32'h0000_2008, 1, 0, 4'b0010, 4'b0010, 4'b0001, 32'h1111_1111); // IO CYCLE read
        check(32'h0000_0040, 1, 0, 4'b0001, 4'b1000, 4'b0000, 32'h0);          // data access to code
        check(32'h0000_3000, 1, 0, 4'b0001, 4'b0001, 4'b0000, 32'h0);          // unmapped
        check(32'h8000_1000, 0, 1, 4'b0001, 4'b0001, 4'b0000, 32'h0);          // high alias
        check(32'h0000_1000, 0, 0, 4'b0000, 4'b0000, 4'b0000, 32'h0);          // no request
        check(32'h0000_2100, 1, 0, 4'b0001, 4'b0001, 4'b0000, 32'h0);          // past IO window

        if (errors == 0) $display("PASS addr_decoder/rw_control : %0d directed tests", tests);
        else             $display("FAIL addr_decoder/rw_control : %0d/%0d failed", errors, tests);
        $finish;
    end
endmodule
