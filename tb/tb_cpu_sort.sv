`timescale 1ns / 1ps

module tb_cpu_sort;

    logic clk = 0;
    logic rst;

    int tests  = 0;
    int errors = 0;

    cpu #(.MEM_FILE("../programs/test_sort.hex")) dut (
        .clk (clk),
        .rst (rst)
    );

    always #5 clk = ~clk;

    // Read a register directly from inside the regfile (hierarchical reference)
    task automatic check_reg(input int r, input logic [31:0] exp);
        logic [31:0] got;
        got = dut.u_regfile.regs[r];
        tests++;
        if (got !== exp) begin
            errors++;
            $display("ERROR x%0d: got=%h exp=%h", r, got, exp);
        end
    endtask

    // Read a data-memory word directly (index = byte address / 4)
    task automatic check_mem(input int idx, input logic [31:0] exp);
        logic [31:0] got;
        got = dut.u_dmem.mem[idx];
        tests++;
        if (got !== exp) begin
            errors++;
            $display("ERROR mem[%0d]: got=%h exp=%h", idx, got, exp);
        end
    endtask

    initial begin
        // Reset, then run well past the end (~101 instructions, then halt)
        rst = 1;
        repeat (2) @(negedge clk);
        rst = 0;
        repeat (150) @(negedge clk);

        // Sorted array: {5, -3, 9, 0} -> {-3, 0, 5, 9}
        check_mem(0, 32'hFFFFFFFD);   // -3: signed compare (BGE) put it first
        check_mem(1, 32'h00000000);
        check_mem(2, 32'h00000005);
        check_mem(3, 32'h00000009);

        // Call / return
        check_reg(1, 32'h00000028);   // ra = address after JAL ra, sort

        // PC must be stuck on "done: JAL x0, done"
        tests++;
        if (dut.pc_cur !== 32'h00000028) begin
            errors++;
            $display("ERROR pc: got=%h exp=00000028", dut.pc_cur);
        end

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule