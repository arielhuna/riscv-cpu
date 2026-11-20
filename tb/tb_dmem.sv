`timescale 1ns / 1ps
module tb_dmem;
    logic        clk, we;
    logic [3:0]  be;
    logic [31:0] addr, wdata, rdata;
    int          errors, tests;
    logic [31:0] rand_addr;

    logic [31:0] model [0:255];

    dmem dut (.clk(clk), .we(we), .be(be), .addr(addr), .wdata(wdata), .rdata(rdata));

    always #5 clk = ~clk;

    // write: DUT gets it through its ports, model updates with a mask
    task automatic write_mem(input logic wen, input logic [3:0] b,
                             input logic [31:0] a, input logic [31:0] d);
        logic [31:0] mask;
        @(negedge clk);
        we = wen; be = b; addr = a; wdata = d;
        @(negedge clk);
        we = 0;
        if (wen) begin
            mask = {{8{b[3]}}, {8{b[2]}}, {8{b[1]}}, {8{b[0]}}};
            model[a[9:2]] = (model[a[9:2]] & ~mask) | (d & mask);
        end
    endtask

    // read: compare DUT to model
    task automatic check_mem(input logic [31:0] a);
        addr = a;
        #1;
        tests++;
        if (rdata !== model[a[9:2]]) begin
            errors++;
            $display("ERROR at %0d: addr=%h -> got=%h expected=%h",
                     $time, a, rdata, model[a[9:2]]);
        end
    endtask

    initial begin
        clk = 0; we = 0; be = 0; addr = 0; wdata = 0;
        errors = 0; tests = 0;

        // 1. Write 0x11223344 to address 0x08 with all bytes enabled
        write_mem(1, 4'b1111, 32'h08, 32'h11223344);
        check_mem(32'h08);
        // 2. Write 0x0000AA00 to address 0x08 with only the second byte enabled
        write_mem(1, 4'b0010, 32'h08, 32'h0000AA00);
        check_mem(32'h08);
        // 3. Write 0xBBCC0000 to address 0x08 with the first and second bytes enabled
        write_mem(1, 4'b1100, 32'h08, 32'hBBCC0000);
        check_mem(32'h08);
        // 4. Write 0x55667788 to address 0x08 with a mix of bytes enabled
        write_mem(1, 4'b1001, 32'h08, 32'h55667788);
        check_mem(32'h08);
        //5. we = 0, check that the data remains unchanged
        write_mem(0, 4'b1111, 32'h08, 32'hFFFFFFFF);
        check_mem(32'h08);
        //6.
        repeat (500) begin
            rand_addr = $urandom_range(0, 63) << 2; // Ensure address is word-aligned
            write_mem($urandom_range(0, 1), $urandom_range(0, 15), rand_addr, $urandom());
            check_mem(rand_addr);
        end

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d errors out of %0d tests", errors, tests);
        $finish;
    end
endmodule
