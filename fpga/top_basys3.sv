`timescale 1ns / 1ps

module top_basys3 #(
    parameter bit    PIPE     = 1,                            // 1 = cpu_pipe, 0 = cpu
    parameter string MEM_FILE = "../programs/test_sort.hex",
    parameter int    CLK_DIV  = 15                            // CPU clock = 1000 / CLK_DIV MHz
) (
    input  logic        clk,     // 100 MHz oscillator
    input  logic        btnC,    // center button = reset
    input  logic [15:0] sw,      // sw[4:0] = register number, sw[15] = upper half
    output logic [15:0] led
);

    // ---------- Clock: 100 MHz -> 1000 MHz (VCO) -> 1000 / CLK_DIV MHz ----------
    logic clk_fb, clk_mmcm, clk_cpu, locked;

    MMCME2_BASE #(
        .CLKIN1_PERIOD    (10.0),       // input: 100 MHz = 10 ns
        .CLKFBOUT_MULT_F  (10.0),       // VCO = 100 x 10 = 1000 MHz
        .CLKOUT0_DIVIDE_F (CLK_DIV)     // output = 1000 / CLK_DIV MHz
    ) u_mmcm (
        .CLKIN1   (clk),
        .CLKFBOUT (clk_fb),             // feedback: the MMCM compares this to CLKIN1
        .CLKFBIN  (clk_fb),
        .CLKOUT0  (clk_mmcm),
        .LOCKED   (locked),             // 1 = output clock is stable
        .RST      (1'b0),
        .PWRDWN   (1'b0)
    );

    BUFG u_bufg (.I(clk_mmcm), .O(clk_cpu));   // global clock buffer: reaches every FF

    // ---------- Reset synchronizer (+ power-on reset) ----------
    logic rst_meta = 1'b1;
    logic rst      = 1'b1;

    always_ff @(posedge clk_cpu) begin
        rst_meta <= btnC | ~locked;   // reset while button pressed OR clock not locked yet
        rst      <= rst_meta;
    end

    // ---------- CPU ----------
    logic [31:0] dbg_data;

    if (PIPE) begin : g_cpu
        cpu_pipe #(.MEM_FILE(MEM_FILE)) u_cpu (
            .clk      (clk_cpu),
            .rst      (rst),
            .dbg_sel  (sw[4:0]),
            .dbg_data (dbg_data)
        );
    end else begin : g_cpu
        cpu #(.MEM_FILE(MEM_FILE)) u_cpu (
            .clk      (clk_cpu),
            .rst      (rst),
            .dbg_sel  (sw[4:0]),
            .dbg_data (dbg_data)
        );
    end

    // ---------- LEDs ----------
    assign led = sw[15] ? dbg_data[31:16] : dbg_data[15:0];

endmodule