`timescale 1ns / 1ps
module tb_imem;
    logic [31:0] addr, instr;
    int          errors, tests;

    imem dut (.addr(addr), .instr(instr));

    task automatic check(input logic [31:0] a, input logic [31:0] expected);
        addr = a;
        #1;
        tests++;
        if (instr !== expected) begin
            errors++;
            $display("ERROR: addr=%h -> instr=%h expected=%h", a, instr, expected);
        end
    endtask

    initial begin
        addr = 0;
        errors = 0; tests = 0;

        check(32'h00, 32'h00000013);
        check(32'h04, 32'h11111111);
        check(32'h08, 32'h22222222);
        check(32'h0A, 32'h22222222);
        check(32'h0C, 32'hDEADBEEF);

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d errors out of %0d tests", errors, tests);
        $finish;
    end
endmodule
