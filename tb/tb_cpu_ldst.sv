`timescale 1ns / 1ps

module tb_cpu_ldst;

    logic clk = 0;
    logic rst;

    int tests  = 0;
    int errors = 0;

    cpu #(.MEM_FILE("../programs/test_ldst.hex")) dut (
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
        // Reset for 2 cycles, then run the 15 instructions
        rst = 1;
        repeat (2) @(negedge clk);
        rst = 0;
        repeat (15) @(negedge clk);

        // Loads from the word built by SB (tests ld_byte, ld_half, extension)
        check_reg(10, 32'hFFFFFF85);   // LB  16
        check_reg(11, 32'h00000085);   // LBU 16
        check_reg(12, 32'hFFFF9285);   // LH  16
        check_reg(13, 32'h00009285);   // LHU 16
        check_reg(14, 32'h00007EF0);   // LH  18 (upper half)
        check_reg(15, 32'h0000007E);   // LB  19 (top byte, positive)

        // Final word after SH (upper half replaced, lower half kept)
        check_mem(4, 32'hFF859285);

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end
endmodule
