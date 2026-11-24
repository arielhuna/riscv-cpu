`timescale 1ns / 1ps

// Signature test: the program stores its results at 0x200 and writes 1 to tohost (0x3FC).
// Both cores run the same program; each signature is dumped to a file and compared to the .ref file.
module tb_cpu_sig;

    localparam string PROG     = "test_sig";
    localparam int    SIG_WORD = 128;           // 0x200 / 4
    localparam int    SIG_LEN  = 8;             // words
    localparam int    TOHOST   = 255;           // 0x3FC / 4
    localparam int    MAX_CYC  = 200;           // timeout

    logic clk = 0;
    logic rst;

    int tests  = 0;
    int errors = 0;
    int cyc    = 0;

    logic [31:0] ref_sig [0:SIG_LEN-1];

    cpu      #(.MEM_FILE({"../programs/", PROG, ".hex"})) dut_sc   (.clk(clk), .rst(rst));
    cpu_pipe #(.MEM_FILE({"../programs/", PROG, ".hex"})) dut_pipe (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    // Compare one word of a signature to the reference
    task automatic check_word(input string name, input int i, input logic [31:0] got);
        tests++;
        if (got !== ref_sig[i]) begin
            errors++;
            $display("ERROR %s sig[%0d] (0x%h): got=%h exp=%h", name, i, (SIG_WORD + i) * 4, got, ref_sig[i]);
        end
    endtask

    initial begin
        $readmemh({"../programs/", PROG, ".ref"}, ref_sig);

        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        // Run until both cores wrote tohost (or timeout)
        while (!(dut_sc.u_dmem.mem[TOHOST] === 32'd1 && dut_pipe.u_dmem.mem[TOHOST] === 32'd1) && cyc < MAX_CYC) begin
            @(posedge clk);
            cyc++;
        end
        if (cyc == MAX_CYC) begin
            errors++;
            $display("ERROR timeout: tohost sc=%h pipe=%h", dut_sc.u_dmem.mem[TOHOST], dut_pipe.u_dmem.mem[TOHOST]);
        end

        // Dump both signatures (build/sig_single.txt, build/sig_pipe.txt)
        $writememh("sig_single.txt", dut_sc.u_dmem.mem,   SIG_WORD, SIG_WORD + SIG_LEN - 1);
        $writememh("sig_pipe.txt",   dut_pipe.u_dmem.mem, SIG_WORD, SIG_WORD + SIG_LEN - 1);

        for (int i = 0; i < SIG_LEN; i++) begin
            check_word("single", i, dut_sc.u_dmem.mem[SIG_WORD + i]);
            check_word("pipe",   i, dut_pipe.u_dmem.mem[SIG_WORD + i]);
        end

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule