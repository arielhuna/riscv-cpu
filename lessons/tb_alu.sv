`timescale 1ns / 1ps
module tb_alu
    import alu_pkg::*;
;
    logic [31:0] a, b;
    alu_op_t  alu_op;
    logic [31:0] result;
    logic        zero;

    alu dut (.a(a), .b(b), .alu_op(alu_op), .result(result), .zero(zero));

    initial begin
        $monitor("op=%-8s a=%h b=%h -> result=%h zero=%b",
            alu_op.name(), a, b, result, zero);

        a = 32'hFFFFFFF8;   // -8
        b = 32'd3;

        alu_op = ALU_ADD; #10;
        alu_op = ALU_SUB; #10;
        alu_op = ALU_SLL; #10;
        alu_op = ALU_SLT; #10;
        alu_op = ALU_SLTU; #10;
        alu_op = ALU_XOR; #10;
        alu_op = ALU_SRL; #10;
        alu_op = ALU_SRA; #10;
        alu_op = ALU_OR; #10;
        alu_op = ALU_AND; #10;

        a = 32'd5;
        b = 32'd5;
        alu_op = ALU_SUB; #10;

        $finish;
    end
endmodule
