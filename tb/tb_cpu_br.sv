`timescale 1ns / 1ps

module tb_cpu_br;

    logic clk = 0;
    logic rst;

    int tests  = 0;
    int errors = 0;

    cpu #(.MEM_FILE("../programs/test_br.hex")) dut (
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
        // Reset, then run well past the end (13 instructions, then halt)
        rst = 1;
        repeat (2) @(negedge clk);
        rst = 0;
        repeat (20) @(negedge clk);

        check_reg(10, 32'hxxxxxxxx);   // BLT taken: marker skipped
        check_reg(11, 32'h00000001);   // BLTU not taken
        check_reg(12, 32'h00000001);   // BGE not taken
        check_reg(13, 32'hxxxxxxxx);   // BGEU taken: marker skipped
        check_reg(5,  32'h12345000);   // LUI
        check_reg(6,  32'h0000102C);   // AUIPC at 0x2C

        // PC must be stuck on "done: JAL x0, done"
        tests++;
        if (dut.pc_cur !== 32'h00000030) begin
            errors++;
            $display("ERROR pc: got=%h exp=00000030", dut.pc_cur);
        end

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule