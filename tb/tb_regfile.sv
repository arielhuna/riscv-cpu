`timescale 1ns / 1ps
module tb_regfile;
    logic        clk, we;
    logic [4:0]  rs1, rs2, rd;
    logic [31:0] rd_data, rs1_data, rs2_data;
    int          errors, tests;

    logic [31:0] model [0:31];           // model of the register file, for checking

    regfile dut (.clk(clk), .we(we), .rs1(rs1), .rs2(rs2), .rd(rd),
                 .rd_data(rd_data), .rs1_data(rs1_data), .rs2_data(rs2_data));

    always #5 clk = ~clk;

    // read from the model, with x0 always returning 0
    function automatic logic [31:0] model_read(input logic [4:0] addr);
        return (addr == 0) ? 32'b0 : model[addr];
    endfunction

    // write to the model, with x0 being ignored
    task automatic write_reg(input logic wen, input logic [4:0] addr, input logic [31:0] data);
        @(negedge clk);
        we = wen; rd = addr; rd_data = data;
        @(negedge clk);                  // wait for the write to take effect
        we = 0;
        if (wen && addr != 0)
            model[addr] = data;
    endtask

    // check the read values
    task automatic check_read(input logic [4:0] a1, a2);
        rs1 = a1; rs2 = a2;
        #1;
        tests++;
        if (rs1_data !== model_read(a1) || rs2_data !== model_read(a2)) begin
            errors++;
            $display("ERROR at %0d: x%0d got=%h exp=%h | x%0d got=%h exp=%h",
                     $time, a1, rs1_data, model_read(a1), a2, rs2_data, model_read(a2));
        end
    endtask

    initial begin
        clk = 0; we = 0; rs1 = 0; rs2 = 0; rd = 0; rd_data = 0;
        errors = 0; tests = 0;

        check_read(0, 0);
        for (int i = 1; i < 32; i++)
            write_reg(1, i, $urandom());
        for (int i = 1; i < 32; i++)
            check_read(i, i);

        write_reg(1, 0, $urandom());
        check_read(0, 0);

        write_reg(0, 5, $urandom());
        check_read(5, 5);

        repeat (500) begin
            write_reg($urandom_range(0, 1), $urandom_range(0, 31), $urandom());
            check_read($urandom_range(0, 31), $urandom_range(0, 31));
        end

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d errors out of %0d tests", errors, tests);
        $finish;
    end
endmodule
