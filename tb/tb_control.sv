`timescale 1ns / 1ps

module tb_control import alu_pkg::*, rv32i_pkg::*; ();

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic       instr30;
    alu_op_t    alu_op;
    logic       alu_src, reg_we, mem_we, branch, jump, jalr;
    logic [1:0] alu_a_sel;
    logic [1:0] wb_sel;

    int tests  = 0;
    int errors = 0;

    control dut (.*);

    // exp layout (14 bits, table order):
    // {alu_op[3:0], alu_src, alu_a_sel[1:0], wb_sel[1:0], reg_we, mem_we, branch, jump, jalr}
    // x in exp = don't care
    task automatic check(
        input string       name,
        input logic [6:0]  op,
        input logic [2:0]  f3,
        input logic        b30,
        input logic [13:0] exp
    );
        logic [13:0] got;
        opcode  = op;
        funct3  = f3;
        instr30 = b30;
        #1;
        got = {alu_op, alu_src, alu_a_sel, wb_sel, reg_we, mem_we, branch, jump, jalr};
        tests++;
        if ($isunknown(got) || !(got ==? exp)) begin
            errors++;
            $display("ERROR %s: got op=%b src=%b asel=%b wb=%b rwe=%b mwe=%b br=%b j=%b jr=%b",
                     name, got[13:10], got[9], got[8:7], got[6:5], got[4], got[3], got[2], got[1], got[0]);
            $display("      %s  exp op=%b src=%b asel=%b wb=%b rwe=%b mwe=%b br=%b j=%b jr=%b",
                     name, exp[13:10], exp[9], exp[8:7], exp[6:5], exp[4], exp[3], exp[2], exp[1], exp[0]);
        end
    endtask

    initial begin
        //     name             opcode      funct3  b30    op  src asel wb rwe mwe br j jr
        check("ADD",           OP_R,      3'b000, 1'b0, 14'b0000_0_00_00_1_0_0_0_0);
        check("LW",            OP_LOAD,   3'b010, 1'b0, 14'b0000_1_00_01_1_0_0_0_0);
        check("SUB",           OP_R,      3'b000, 1'b1, 14'b1000_0_00_00_1_0_0_0_0);
        check("ADDI positive", OP_IMM,    3'b000, 1'b0, 14'b0000_1_00_00_1_0_0_0_0);
        check("ADDI negative", OP_IMM,    3'b000, 1'b1, 14'b0000_1_00_00_1_0_0_0_0);
        check("SRAI",          OP_IMM,    3'b101, 1'b1, 14'b1101_1_00_00_1_0_0_0_0);
        check("SW",            OP_STORE,  3'b010, 1'b0, 14'b0000_1_00_xx_0_1_0_0_0);
        check("BNE",           OP_BRANCH, 3'b001, 1'b1, 14'b1000_0_00_xx_0_0_1_0_0);
        check("JAL",           OP_JAL,    3'b000, 1'b0, 14'bxxxx_x_xx_10_1_0_0_1_0);
        check("JALR",          OP_JALR,   3'b000, 1'b0, 14'b0000_1_00_10_1_0_0_0_1);
        check("LUI",           OP_LUI,    3'b000, 1'b0, 14'b0000_1_10_00_1_0_0_0_0);
        check("AUIPC",         OP_AUIPC,  3'b000, 1'b0, 14'b0000_1_01_00_1_0_0_0_0);
        check("unknown",       7'b1111111,3'b000, 1'b0, 14'bxxxx_x_xx_xx_0_0_0_0_0);

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule