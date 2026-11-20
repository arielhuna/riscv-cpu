`timescale 1ns / 1ps

module tb_cpu;

    logic clk = 0;
    logic rst;

    int tests  = 0;
    int errors = 0;

    cpu #(.MEM_FILE("../programs/test_ri.hex")) dut (
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

    initial begin
        // Reset for 2 cycles, then run the 8 instructions
        rst = 1;
        repeat (2) @(negedge clk);
        rst = 0;
        repeat (8) @(negedge clk);

        check_reg(5, 32'h00000005);
        check_reg(6, 32'h00000003);
        check_reg(7, 32'h00000008);
        check_reg(8, 32'h00000002);
        check_reg(9, 32'hFFFFFFF0);
        check_reg(10, 32'hFFFFFFFC);
        check_reg(11, 32'hFFFFFFFA);
        check_reg(0, 32'hxxxxxxxx);   // x0 must never be written

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule
