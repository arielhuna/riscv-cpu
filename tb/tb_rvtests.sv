`timescale 1ns / 1ps

// Official riscv-tests (rv32ui) on both cores.
// For each test in rvtests/list.txt: load imem + dmem, reset, wait for tohost.
// tohost = 1: pass; (n << 1) | 1: test case n failed.
module tb_rvtests;

    localparam int TOHOST  = 255;               // 0x3FC / 4
    localparam int MAX_CYC = 5000;              // timeout per test

    logic clk = 0;
    logic rst = 1;

    int tests  = 0;
    int errors = 0;

    cpu      dut_sc   (.clk(clk), .rst(rst));
    cpu_pipe dut_pipe (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    // Report one core's result for the current test
    task automatic check(input string core, input string name, input logic [31:0] th);
        tests++;
        if (th !== 32'd1) begin
            errors++;
            if (th === 32'hxxxxxxxx) $display("ERROR %-6s %-6s: timeout, tohost never written", core, name);
            else                     $display("ERROR %-6s %-6s: tohost = %h, test case %0d failed", core, name, th, th >> 1);
        end
    endtask

    int    fd;
    int    cyc;
    string name;

    initial begin
        fd = $fopen("../rvtests/list.txt", "r");
        if (fd == 0) begin
            $display("FAILED: cannot open ../rvtests/list.txt");
            $finish;
        end

        while ($fscanf(fd, "%s", name) == 1) begin
            // Clear both memories (no leftovers from the previous test), then load program and data
            rst = 1;
            for (int i = 0; i < 1024; i++) begin
                dut_sc.u_imem.mem[i]   = 32'hxxxxxxxx;
                dut_pipe.u_imem.mem[i] = 32'hxxxxxxxx;
            end
            for (int i = 0; i < 256; i++) begin
                dut_sc.u_dmem.mem[i]   = 32'hxxxxxxxx;
                dut_pipe.u_dmem.mem[i] = 32'hxxxxxxxx;
            end
            $readmemh({"../rvtests/hex/", name, ".hex"},      dut_sc.u_imem.mem);
            $readmemh({"../rvtests/hex/", name, ".hex"},      dut_pipe.u_imem.mem);
            $readmemh({"../rvtests/hex/", name, ".data.hex"}, dut_sc.u_dmem.mem);
            $readmemh({"../rvtests/hex/", name, ".data.hex"}, dut_pipe.u_dmem.mem);

            repeat (2) @(posedge clk);
            rst = 0;

            // Run until both cores wrote tohost (or timeout)
            cyc = 0;
            while ((dut_sc.u_dmem.mem[TOHOST] === 32'hxxxxxxxx || dut_pipe.u_dmem.mem[TOHOST] === 32'hxxxxxxxx)
                   && cyc < MAX_CYC) begin
                @(posedge clk);
                cyc++;
            end

            check("single", name, dut_sc.u_dmem.mem[TOHOST]);
            check("pipe",   name, dut_pipe.u_dmem.mem[TOHOST]);
        end
        $fclose(fd);

        if (errors == 0) $display("PASSED: %0d tests", tests);
        else             $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule