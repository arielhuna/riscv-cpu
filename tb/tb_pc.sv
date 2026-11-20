`timescale 1ns / 1ps
module tb_pc;
    logic        clk, rst;
    logic [31:0] pc_next, pc;
    int          errors, tests;

    pc dut (.clk(clk), .rst(rst), .pc_next(pc_next), .pc(pc));

    always #5 clk = ~clk;

    // one clock cycle: set inputs, let posedge happen, check result
    task automatic step(input logic r, input logic [31:0] next, input logic [31:0] expected);
        @(negedge clk);
        rst = r; pc_next = next;
        @(negedge clk);
        tests++;
        if (pc !== expected) begin
            errors++;
            $display("ERROR at %0d: rst=%b pc_next=%h -> pc=%h expected=%h",
                     $time, r, next, pc, expected);
        end
    endtask

    initial begin
        clk = 0; rst = 0; pc_next = 0;
        errors = 0; tests = 0;

        step(1, 32'hDEADBEEF, 32'b0);

        repeat (10) begin
            step(0, pc + 4, pc + 4);
        end

        step(0, 32'h100, 32'h100);
        step(1, 32'hDEADBEEF, 32'b0);

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d errors out of %0d tests", errors, tests);
        $finish;
    end
endmodule
