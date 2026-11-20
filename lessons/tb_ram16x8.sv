`timescale 1ns / 1ps
module tb_ram16x8;
    logic clk = 0;
    always #5 clk = ~clk;

    logic     we;
    logic [3:0] addr;
    logic [7:0] wdata;
    logic [7:0] rdata;

    ram16x8 dut (.clk(clk), .we(we), .addr(addr), .wdata(wdata), .rdata(rdata));

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_ram16x8);
        $monitor("t=%0d we=%b addr=%h wdata=%h -> rdata=%h",
                 $time, we, addr, wdata, rdata);

        we = 0; addr = 4'h0; wdata = 8'h00;

        for (int i = 0; i < 4; i++) begin
            @(negedge clk);
            addr = i;
        end

        @(negedge clk);
        we = 1; wdata = 8'hAB;
        @(negedge clk);
        we = 0;
        @(negedge clk);
        wdata = 8'hFF;
        @(negedge clk);
        addr = 5;
        @(negedge clk);
        $finish;
    end
endmodule
