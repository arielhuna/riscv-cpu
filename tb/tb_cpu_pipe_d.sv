`timescale 1ns / 1ps

module tb_cpu_pipe_d;

    logic clk = 0;
    logic rst;

    int tests  = 0;
    int errors = 0;
    int stalls = 0;

    cpu_pipe #(.MEM_FILE("../programs/test_pipe_d.hex")) dut (
        .clk (clk),
        .rst (rst)
    );

    always #5 clk = ~clk;

    // Count load-use stall cycles
    always @(posedge clk)
        if (!rst && dut.stall) stalls++;

    task automatic check_reg(input int r, input logic [31:0] exp);
        logic [31:0] got;
        got = dut.u_regfile.regs[r];
        tests++;
        if (got !== exp) begin
            errors++;
            $display("ERROR x%0d: got=%h exp=%h", r, got, exp);
        end
    endtask

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
        rst = 1;
        repeat (2) @(negedge clk);
        rst = 0;
        // 15 instructions + 2 NOPs behind blt run until done,
        // + 4 stall cycles + 4 cycles to drain the pipe, + margin
        repeat (40) @(negedge clk);

        check_reg(13, 32'h00000063);   // a3 = 99
        check_reg(18, 32'h00000001);   // s2 = 1
        check_reg(14, 32'h00000063);   // a4 = LW
        check_reg(15, 32'h00000064);   // a5 = a4 + s2   (load-use on rs1)
        check_reg(16, 32'h00000063);   // a6 = LW
        check_reg(28, 32'hFFFFFFFF);   // t3 = -1
        check_reg(29, 32'hFFFFFFFF);   // t4 = LW of -1
        check_reg(30, 32'hxxxxxxxx);   // t5 never written (blt taken)
        check_reg(19, 32'h00000063);   // s3 = LW
        check_reg(20, 32'h000000C6);   // s4 = s3 + s3   (rs1 and rs2)

        check_mem(16, 32'h00000063);   // SW a3
        check_mem(17, 32'h00000063);   // SW a6: load-use on store data
        check_mem(18, 32'hFFFFFFFF);   // SW t3

        // Exactly one stall per load-use pair: add, sw, blt, add
        tests++;
        if (stalls != 4) begin
            errors++;
            $display("ERROR stalls: got=%0d exp=4", stalls);
        end

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule
