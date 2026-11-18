`timescale 1ns / 1ps

module cpu_pipe import alu_pkg::*, rv32i_pkg::*, pipe_pkg::*; #(
    parameter string MEM_FILE = "../programs/sum.hex"
) (
    input  logic clk,
    input  logic rst
);

    // ==================== IF ====================
    logic [31:0] pc_cur, pc_next, pc_plus4;
    logic [31:0] instr;

    pc u_pc (
        .clk     (clk),
        .rst     (rst),
        .pc_next (pc_next),
        .pc      (pc_cur)
    );

    imem #(.MEM_FILE(MEM_FILE)) u_imem (
        .addr  (pc_cur),
        .instr (instr)
    );

    assign pc_plus4 = pc_cur + 32'd4;

    // ---------- IF/ID register ----------
    if_id_t if_id;

    always_ff @(posedge clk) begin
        if (rst) begin
            if_id.pc    <= 32'h0;
            if_id.instr <= 32'h00000013;   // NOP = ADDI x0, x0, 0
        end else begin
            if_id.pc    <= pc_cur;         // address of THIS instruction
            if_id.instr <= instr;
        end
    end

    // ==================== ID ====================
    // Instruction fields: from IF/ID, not from imem
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic        instr30;
    logic [4:0]  rs1, rs2, rd;

    assign opcode  = if_id.instr[6:0];
    assign rd      = if_id.instr[11:7];
    assign funct3  = if_id.instr[14:12];
    assign rs1     = if_id.instr[19:15];
    assign rs2     = if_id.instr[24:20];
    assign instr30 = if_id.instr[30];

    // Immediate
    logic [31:0] imm;

    immgen u_immgen (
        .instr (if_id.instr),
        .imm   (imm)
    );

    // Control signals
    alu_op_t     alu_op;
    logic        alu_src, reg_we, mem_we, branch, jump, jalr;
    logic [1:0]  wb_sel;
    logic [1:0]  alu_a_sel;

    control u_control (
        .opcode    (opcode),
        .funct3    (funct3),
        .instr30   (instr30),
        .alu_op    (alu_op),
        .alu_src   (alu_src),
        .alu_a_sel (alu_a_sel),
        .wb_sel    (wb_sel),
        .reg_we    (reg_we),
        .mem_we    (mem_we),
        .branch    (branch),
        .jump      (jump),
        .jalr      (jalr)
    );

    // Register file: read in ID, write comes from WB
    logic [31:0] rs1_data, rs2_data;
    logic        wb_we;
    logic [4:0]  wb_rd;
    logic [31:0] wb_data;

    assign wb_we   = 1'b0;      // TEMP: driven by MEM/WB in lesson 26b
    assign wb_rd   = 5'd0;      // TEMP
    assign wb_data = 32'h0;     // TEMP

    regfile u_regfile (
        .clk      (clk),
        .we       (wb_we),
        .rs1      (rs1),
        .rs2      (rs2),
        .rd       (wb_rd),
        .rd_data  (wb_data),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    // ---------- ID/EX register ----------
    id_ex_t id_ex;

    always_ff @(posedge clk) begin
        if (rst) begin
            id_ex <= '0;               // all control = 0 -> NOP
        end else begin
            // data
            id_ex.pc        <= if_id.pc;
            id_ex.rs1_data  <= rs1_data;
            id_ex.rs2_data  <= rs2_data;
            id_ex.imm       <= imm;
            // fields
            id_ex.rd        <= rd;
            id_ex.rs1       <= rs1;
            id_ex.rs2       <= rs2;
            id_ex.funct3    <= funct3;
            // control
            id_ex.alu_op    <= alu_op;
            id_ex.alu_a_sel <= alu_a_sel;
            id_ex.wb_sel    <= wb_sel;
            id_ex.alu_src   <= alu_src;
            id_ex.reg_we    <= reg_we;
            id_ex.mem_we    <= mem_we;
            id_ex.branch    <= branch;
            id_ex.jump      <= jump;
            id_ex.jalr      <= jalr;
        end
    end

    // ==================== EX ====================
    // Everything here comes from the ID/EX card
    logic [31:0] alu_a, alu_b;
    logic [31:0] alu_out;
    logic        alu_zero;

    always_comb begin
        case (id_ex.alu_a_sel)
            2'd1:    alu_a = id_ex.pc;          // AUIPC
            2'd2:    alu_a = 32'h00000000;      // LUI
            default: alu_a = id_ex.rs1_data;
        endcase
    end
    assign alu_b = id_ex.alu_src ? id_ex.imm : id_ex.rs2_data;

    alu u_alu (
        .a      (alu_a),
        .b      (alu_b),
        .alu_op (id_ex.alu_op),
        .zero   (alu_zero),
        .result (alu_out)
    );

    // ---------- Branch / jump target ----------
    logic [31:0] pc_target;
    assign pc_target = id_ex.pc + id_ex.imm;    // PC of THIS instruction

    logic lt, ltu;
    assign lt  = $signed(id_ex.rs1_data) < $signed(id_ex.rs2_data);
    assign ltu = id_ex.rs1_data < id_ex.rs2_data;

    // ---------- Branch decision ----------
    logic br_cond, take_branch;

    always_comb begin
        case (id_ex.funct3)
            3'b000:  br_cond = alu_zero;        // BEQ
            3'b001:  br_cond = ~alu_zero;       // BNE
            3'b100:  br_cond = lt;              // BLT
            3'b101:  br_cond = ~lt;             // BGE
            3'b110:  br_cond = ltu;             // BLTU
            3'b111:  br_cond = ~ltu;            // BGEU
            default: br_cond = 1'b0;
        endcase
    end
    assign take_branch = id_ex.branch & br_cond;



    // ---------- Next PC ----------
    always_comb begin
        case ({id_ex.jalr, id_ex.jump | take_branch})
            2'b10:   pc_next = {alu_out[31:1], 1'b0};  // JALR
            2'b01:   pc_next = pc_target;              // JAL, taken branch
            default: pc_next = pc_plus4;               // keep fetching
        endcase
    end


    // ---------- EX/MEM register ----------
    ex_mem_t ex_mem;

    always_ff @(posedge clk) begin
        if (rst) begin
            ex_mem <= '0;                          // reg_we = mem_we = 0 -> NOP
        end else begin
            // data
            ex_mem.pc_plus4 <= id_ex.pc + 32'd4;             // THIS instruction's pc + 4
            ex_mem.alu_out  <= alu_out;               // born in EX
            ex_mem.rs2_data <= id_ex.rs2_data;               // x5 for SW
            // fields
            ex_mem.rd       <= id_ex.rd;
            ex_mem.funct3   <= id_ex.funct3;
            // control
            ex_mem.mem_we   <= id_ex.mem_we;
            ex_mem.wb_sel   <= id_ex.wb_sel;
            ex_mem.reg_we   <= id_ex.reg_we;
        end
    end

endmodule