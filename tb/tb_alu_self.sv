`timescale 1ns / 1ps
module tb_alu_self
    import alu_pkg::*;
;
    logic [31:0] a, b;
    alu_op_t     alu_op;
    logic [31:0] result;
    logic        zero;
    int          errors;
    int          tests;

    // array of all ALU operations
    alu_op_t all_ops[10] = '{ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
                             ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND};

    // array of edge values for testing
    logic [31:0] edge_vals[7] = '{32'h00000000, 32'h00000001, 32'hFFFFFFFF,
                                  32'h80000000, 32'h7FFFFFFF, 32'd31, 32'd32};

    alu dut (.a(a), .b(b), .alu_op(alu_op), .result(result), .zero(zero));

    // expected result function for ALU operations
    function automatic logic [31:0] alu_ref(
        input logic [31:0] x, y,
        input alu_op_t     op
    );
        case (op)
            ALU_ADD:  return x + y;
            ALU_SUB:  return x - y;
            ALU_SLL:  return x << y[4:0];
            ALU_SLT:  return {31'b0, ($signed(x) < $signed(y))};
            ALU_SLTU: return {31'b0, (x < y)};
            ALU_XOR:  return x ^ y;
            ALU_SRL:  return x >> y[4:0];
            ALU_SRA:  return $signed(x) >>> y[4:0];
            ALU_OR:   return x | y;
            ALU_AND:  return x & y;
            default:  return 32'b0;
        endcase
    endfunction

    //
    task automatic check(
        input logic [31:0] ta, tb_,
        input alu_op_t     top
    );
        logic [31:0] expected;
        logic  zero_expected;

        a = ta;
        b = tb_;
        alu_op = top;
        #1;

        tests++;                                          // NEW
        expected = alu_ref(ta, tb_, top);
        zero_expected = (expected == 32'h0);
        if (result !== expected || zero !== zero_expected) begin
            errors++;
            $display("ERROR at %0d: op=%-8s a=%h b=%h-> got=%h expected=%h, zero=%b expected_zero=%b",
                     $time, top.name(), ta, tb_, result, expected, zero, zero_expected);
        end
    endtask

    initial begin
        a = 0; b = 0; alu_op = ALU_ADD;
        errors = 0;
        tests  = 0;

        // edge case tests: all combinations of edge values for each operation
        foreach (all_ops[k])
            foreach (edge_vals[i])
                foreach (edge_vals[j])
                    check(edge_vals[i], edge_vals[j], all_ops[k]);

        // random tests: 500 random tests for each operation
        foreach (all_ops[k])
            repeat (500)
                check($urandom, $urandom, all_ops[k]);

        // report results
        if (errors == 0)
            $display("PASSED: %0d tests", tests);
        else
            $display("FAILED: %0d errors out of %0d tests", errors, tests);

        $finish;
    end
endmodule
