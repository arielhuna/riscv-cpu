`timescale 1ns / 1ps

module tb_cpu_pipe_b;

    logic clk = 0;
    logic rst;

    int tests  = 0;
    int errors = 0;

    cpu_pipe #(.MEM_FILE("../programs/test_pipe_b.hex")) dut (
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
        // 25 instructions run until skip (incl. NOPs and the 2 behind each jump)
        // + 4 cycles to drain the pipe, + margin
        repeat (40) @(negedge clk);

        check_reg(5,  32'h00000005);   // t0
        check_reg(6,  32'hFFFFFFFD);   // t1
        check_reg(10, 32'h00000040);   // a0
        check_reg(7,  32'h00000002);   // t2 = t0 + t1
        check_reg(8,  32'h00000005);   // s0 = LW
        check_reg(9,  32'hFFFFFFFD);   // s1 = LB  (sign extended)
        check_reg(18, 32'h000000FD);   // s2 = LBU (zero extended)
        check_reg(19, 32'h12345000);   // s3 = LUI
        check_reg(1,  32'h00000034);   // ra = pc + 4 of the JAL at 0x30
        check_reg(11, 32'h00000007);   // a1 (set inside func)
        check_reg(20, 32'h00000001);   // s4 = 1, the addi 99 was skipped

        check_mem(16, 32'h00000005);   // SW  at 64
        check_mem(17, 32'hxxxxxxFD);   // SB  at 68: only byte 0 written

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule