`timescale 1ns / 1ps

module tb_cpu_pipe_a;

    logic clk = 0;
    logic rst;

    int tests  = 0;
    int errors = 0;

    cpu_pipe #(.MEM_FILE("../programs/test_pipe_a.hex")) dut (
        .clk (clk),
        .rst (rst)
    );

    always #5 clk = ~clk;

    // Generic 32-bit check with a name for the message
    task automatic check(input string name, input logic [31:0] got, input logic [31:0] exp);
        tests++;
        if (got !== exp) begin
            errors++;
            $display("ERROR %s: got=%h exp=%h", name, got, exp);
        end
    endtask

    initial begin
        rst = 1;
        repeat (2) @(negedge clk);
        rst = 0;

        // Cycle 0 (still the reset cards)
        check("c0 if_id.instr",  dut.if_id.instr, 32'h00000013);   // NOP
        check("c0 id_ex.reg_we", dut.id_ex.reg_we, 1'b0);

        // Cycle 1: addi t0 in ID
        @(negedge clk);
        check("c1 if_id.pc",     dut.if_id.pc,    32'h00000000);
        check("c1 if_id.instr",  dut.if_id.instr, 32'h00500293);
        check("c1 pc_cur",       dut.pc_cur,      32'h00000004);

        // Cycle 2: addi t0 in EX
        @(negedge clk);
        check("c2 id_ex.pc",     dut.id_ex.pc,     32'h00000000);
        check("c2 id_ex.rd",     dut.id_ex.rd,     5'd5);
        check("c2 id_ex.reg_we", dut.id_ex.reg_we, 1'b1);
        check("c2 alu_out",      dut.alu_out,      32'h00000005);
        check("c2 if_id.pc",     dut.if_id.pc,     32'h00000004);

        // Cycle 3: addi t1, -3 in EX
        @(negedge clk);
        check("c3 id_ex.pc",     dut.id_ex.pc,     32'h00000004);
        check("c3 id_ex.imm",    dut.id_ex.imm,    32'hFFFFFFFD);
        check("c3 alu_out",      dut.alu_out,      32'hFFFFFFFD);

        // Cycle 4: lui t2 in EX
        @(negedge clk);
        check("c4 id_ex.rd",     dut.id_ex.rd,     5'd7);
        check("c4 alu_out",      dut.alu_out,      32'h12345000);

        // Cycle 5: auipc t3 at 0x0C in EX (uses id_ex.pc, not pc_cur)
        @(negedge clk);
        check("c5 id_ex.pc",     dut.id_ex.pc,     32'h0000000C);
        check("c5 pc_cur",       dut.pc_cur,       32'h00000014);
        check("c5 alu_out",      dut.alu_out,      32'h0000100C);

        // Cycle 6: done (jal) at 0x10 in EX -> redirect
        @(negedge clk);
        check("c6 id_ex.jump",   dut.id_ex.jump,   1'b1);
        check("c6 pc_target",    dut.pc_target,    32'h00000010);
        check("c6 pc_next",      dut.pc_next,      32'h00000010);

        // Cycle 7: PC is back on done
        @(negedge clk);
        check("c7 pc_cur",       dut.pc_cur,       32'h00000010);

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule