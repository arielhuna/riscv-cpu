`timescale 1ns / 1ps
module dmem (
    input  logic        clk,
    input  logic        we,
    input  logic [3:0]  be,        // byte enable: one bit per byte
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);
    logic [31:0] mem [0:255];

    always_ff @(posedge clk) begin
        if (we) begin
            if (be[0]) mem[addr[9:2]][7:0]   <= wdata[7:0];
            if (be[1]) mem[addr[9:2]][15:8]  <= wdata[15:8];
            if (be[2]) mem[addr[9:2]][23:16] <= wdata[23:16];
            if (be[3]) mem[addr[9:2]][31:24] <= wdata[31:24];
        end
    end
    assign rdata = mem[addr[9:2]];
endmodule
