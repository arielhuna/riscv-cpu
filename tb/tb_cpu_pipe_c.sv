`timescale 1ns / 1ps

module tb_cpu_pipe_c;

    logic clk = 0;
    logic rst;

    int tests  = 0;
    int errors = 0;

    cpu_pipe #(.MEM_FILE("../programs/test_pipe_c.hex")) dut (
        .clk (clk),
        .rst (rst)
    );

    always #5 clk = ~clk;

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
        // 23 instructions run until done (incl. the 2 NOPs behind blt)
        // + 4 cycles to drain the pipe, + margin
        repeat (40) @(negedge clk);

        check_reg(5,  32'h00000005);   // t0
        check_reg(6,  32'hFFFFFFFD);   // t1
        check_reg(7,  32'h00000002);   // t2 = t0 + t1  (WB + MEM forwarding)
        check_reg(8,  32'h00000002);   // s0 = newer value
        check_reg(9,  32'h00000004);   // s1 = 2 + 2    (MEM wins over WB)
        check_reg(11, 32'h0000000E);   // a1 = 7 + 7    (WB->ID bypass)
        check_reg(13, 32'h00000063);   // a3 = 99
        check_reg(14, 32'h00000063);   // a4 = LW
        check_reg(15, 32'h00000064);   // a5 = a4 + s2  (load value from WB)
        check_reg(31, 32'h00000000);   // t6 = x0 + x0  (no forwarding to x0)
        check_reg(30, 32'h00000001);   // t5 = 1
        check_reg(29, 32'hxxxxxxxx);   // t4 never written (branch taken)

        check_mem(16, 32'h00000063);   // SW: forwarded store data

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule