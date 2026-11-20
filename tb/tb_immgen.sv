`timescale 1ns / 1ps
module tb_immgen
    import rv32i_pkg::*;
;
    logic [31:0] instr, imm;
    logic [31:0] v, expected;
    int          errors, tests;

    immgen dut (.instr(instr), .imm(imm));

    task automatic check(input logic [31:0] i, input logic [31:0] exp, input string fmt);
        instr = i;
        #1;
        tests++;
        if (imm !== exp) begin
            errors++;
            $display("ERROR [%s]: instr=%h -> imm=%h expected=%h", fmt, i, imm, exp);
        end
    endtask

    initial begin
        instr = 0; errors = 0; tests = 0;

        // ---- I-type tests ----
        repeat (200) begin
            v = $urandom();
            expected = {{20{v[11]}}, v[11:0]};      // the value: random 12-bit signed
            instr = $urandom();                      // random rs1, rd, funct3...
            instr[31:20] = expected[11:0];           // encode: put imm where I-type keeps it
            instr[6:0]   = OP_IMM;
            check(instr, expected, "I");
        end

        // ---- S-type tests ----
        repeat (200) begin
            v = $urandom();
            expected = {{20{v[11]}}, v[11:5], v[4:0]};      // the value: random 12-bit signed
            instr = $urandom();                      // random rs1, rs2, funct3...
            instr[31:25] = expected[11:5];
            instr[11:7] = expected[4:0];           // encode: put imm where S-type keeps it
            instr[6:0]   = OP_STORE;
            check(instr, expected, "S");
        end

        // ---- B-type tests ----
        repeat (200) begin
            v = $urandom();
            expected = {{19{v[12]}}, v[12:1], 1'b0}; // the value: random 13-bit signed, LSB is always 0
            instr = $urandom();                 // random rs1, rs2, funct3...
            instr[31]    = expected[12];        // the sign bit
            instr[30:25] = expected[10:5];
            instr[11:8]  = expected[4:1];
            instr[7]     = expected[11];        // the 12th bit
            instr[6:0]   = OP_BRANCH;
            check(instr, expected, "B");
        end

        // ---- U-type tests ----
        repeat (200) begin
            v = $urandom();
            expected = {{v[19:0]}, 12'b0}; // the value: random 20-bit unsigned, LSBs are always 0
            instr = $urandom();                 // random rs1, rs2, funct3...
            instr[31:12] = expected[31:12];
            instr[6:0]   = OP_LUI;
            check(instr, expected, "U");
        end

        // ---- J-type tests ----
        repeat (200) begin
            v = $urandom();
            expected = {{11{v[20]}}, v[20:1], 1'b0}; // the value: random 21-bit signed, LSB is always 0
            instr = $urandom();                 // random rs1, rs2, funct3...
            instr[31]    = expected[20];        // the sign bit
            instr[30:21] = expected[10:1];
            instr[20]    = expected[11];        // the 12th bit
            instr[19:12] = expected[19:12];
            instr[6:0]   = OP_JAL;
            check(instr, expected, "J");
        end

        // ---- R-type tests ----
        repeat (200) begin
            v = $urandom();
            expected = 32'b0; // R-type has no immediate
            instr = $urandom();                 // random rs1, rs2, funct3...
            instr[6:0]   = OP_R;              // any R-type opcode
            check(instr, expected, "R");
        end

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d errors out of %0d tests", errors, tests);
        $finish;
    end
endmodule
