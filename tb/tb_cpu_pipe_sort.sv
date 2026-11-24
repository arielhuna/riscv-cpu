`timescale 1ns / 1ps

module tb_cpu_pipe_sort;

    logic clk = 0;
    logic rst;

    int tests   = 0;
    int errors  = 0;
    int cycles  = 0;
    int stalls  = 0;
    int flushes = 0;
    bit at_done = 0;

    cpu_pipe #(.MEM_FILE("../programs/test_sort.hex")) dut (
        .clk (clk),
        .rst (rst)
    );

    always #5 clk = ~clk;

    // Measure until "done: JAL x0, done" (0x28) reaches EX = the program is over
    always @(posedge clk)
        if (!rst && !at_done) begin
            cycles++;
            if (dut.id_ex.jump && dut.id_ex.pc == 32'h28) at_done = 1;
            else begin
                if (dut.stall) stalls++;
                if (dut.flush) flushes++;
            end
        end

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
        // 101 instructions (single-cycle) + 4 fill + 9 stalls + 2 x 24 flushes = 162 by formula
        // (161 until done reaches EX), + margin
        repeat (200) @(negedge clk);

        // Same results as tb_cpu_sort: {5, -3, 9, 0} -> {-3, 0, 5, 9}
        check_mem(0, 32'hFFFFFFFD);
        check_mem(1, 32'h00000000);
        check_mem(2, 32'h00000005);
        check_mem(3, 32'h00000009);
        check_reg(1, 32'h00000028);    // ra = address after JAL ra, sort

        // Hazards predicted on paper (lesson 30a)
        check_cnt("reached done", at_done, 1);
        check_cnt("stalls",  stalls,  9);    // LW t5 -> BGE t5, 3 passes x 3
        check_cnt("flushes", flushes, 24);   // taken branches + jumps

        $display("INFO: %0d cycles to done, %0d stalls, %0d flushes, CPI = %.2f (101 instructions)",
                 cycles, stalls, flushes, real'(cycles) / 101.0);

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule
