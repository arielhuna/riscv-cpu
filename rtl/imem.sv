`timescale 1ns / 1ps
module imem #(
    parameter string MEM_FILE = "../programs/imem_test.hex"
) (
    input  logic [31:0] addr,
    output logic [31:0] instr
);
    logic [31:0] mem [0:1023];

    initial begin
        $readmemh(MEM_FILE, mem);
    end
    assign instr = mem[addr[11:2]];
endmodule
