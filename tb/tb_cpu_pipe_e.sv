`timescale 1ns / 1ps

module tb_cpu_pipe_e;

    logic clk = 0;
    logic rst;

    int tests   = 0;
    int errors  = 0;
    int stalls  = 0;
    int flushes = 0;

    cpu_pipe #(.MEM_FILE("../programs/test_pipe_e.hex")) dut (
        .clk (clk),
        .rst (rst)
    );

    always #5 clk = ~clk;

    // Count load-use stall cycles
    always @(posedge clk)
        if (!rst && dut.stall) stalls++;

    // Count flush cycles, except the endless "done: jal x0, done" loop (0x3C)
    always @(posedge clk)
        if (!rst && dut.flush && dut.id_ex.pc != 32'h3C) flushes++;

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

    task automatic check_cnt(input string name, input int got, input int exp);
        tests++;
        if (got != exp) begin
            errors++;
            $display("ERROR %s: got=%0d exp=%0d", name, got, exp);
        end
    endtask

    initial begin
        rst = 1;
        repeat (2) @(negedge clk);
        rst = 0;
        // 14 instructions run until done, + 5 flushes x 2 + 1 stall
        // + 4 cycles to drain the pipe = 29, + margin
        repeat (50) @(negedge clk);

        // Right path: must run
        check_reg(5,  32'h00000005);   // t0 = 5
        check_reg(6,  32'h00000005);   // t1 = 5
        check_reg(9,  32'h00000001);   // s1 = 1   (target of the taken beq)
        check_reg(18, 32'h00000002);   // s2 = 2   (after the NOT taken bne)
        check_reg(1,  32'h0000002C);   // ra = 0x2C
        check_reg(12, 32'h00000005);   // a2 = LW
        check_reg(19, 32'h00000001);   // s3 = 1   (runs once, after ret)
        check_mem(16, 32'h00000005);   // SW t0

        // Wrong path: must never run
        check_reg(8,  32'hxxxxxxxx);   // s0  (behind beq, in ID)
        check_reg(26, 32'hxxxxxxxx);   // s10 (wrong-path "jal x0, bad" must not redirect)
        check_reg(20, 32'hxxxxxxxx);   // s4  (behind bnez)
        check_reg(22, 32'hxxxxxxxx);   // s6  (behind beq after the stall)
        check_reg(24, 32'hxxxxxxxx);   // s8  (behind ret)

        // beq, jal, beq, ret, bnez -> 5 flushes; lw -> beq -> 1 stall
        check_cnt("flushes", flushes, 5);
        check_cnt("stalls",  stalls,  1);

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule