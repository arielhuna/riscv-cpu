`timescale 1ns / 1ps

module tb_cpu_sum;

    logic clk = 0;
    logic rst;

    int tests  = 0;
    int errors = 0;

    cpu #(.MEM_FILE("../programs/sum.hex")) dut (
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
        // Reset for 2 cycles, then run well past the end (19 instructions)
        rst = 1;
        repeat (2) @(negedge clk);
        rst = 0;
        repeat (30) @(negedge clk);

        check_reg(5, 32'h0000000F);   // sum = 1+2+3+4+5
        check_reg(6, 32'h00000006);   // i after the last i++
        check_reg(7, 32'h00000006);   // limit, unchanged
        check_mem(0, 32'h0000000F);   // SW stored the sum

        // PC must be stuck on "done: JAL x0, done"
        tests++;
        if (dut.pc_cur !== 32'h0000001C) begin
            errors++;
            $display("ERROR pc: got=%h exp=0000001c", dut.pc_cur);
        end

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule
