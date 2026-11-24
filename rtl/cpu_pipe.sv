`timescale 1ns / 1ps

module cpu_pipe import alu_pkg::*, rv32i_pkg::*, pipe_pkg::*; #(
    parameter string MEM_FILE = "../programs/sum.hex"
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [4:0]  dbg_sel,      // debug: register number
    output logic [31:0] dbg_data      // debug: its value
);

    // ==================== IF ====================
    logic [31:0] pc_cur, pc_next, pc_plus4;
    logic [31:0] instr;
    logic        stall;    // from hazard unit in ID, used by IF too
    logic        flush;    // from EX (taken branch / jump), used by IF/ID and ID/EX

    // Pipeline cards (declared first: earlier stages read later cards)
    if_id_t  if_id;
    id_ex_t  id_ex;
    ex_mem_t ex_mem;
    mem_wb_t mem_wb;

    pc u_pc (
        .clk     (clk),
        .rst     (rst),
        .pc_next (stall ? pc_cur : pc_next),
        .pc      (pc_cur)
    );

    imem #(.MEM_FILE(MEM_FILE)) u_imem (
        .addr  (pc_cur),
        .instr (instr)
    );

    assign pc_plus4 = pc_cur + 32'd4;

    // ---------- IF/ID register ----------
    always_ff @(posedge clk) begin
        // pc + instr[31:12]: don't care on flush, so only reset and stall touch them
        if (rst) begin
            if_id.pc           <= 32'h0;
            if_id.instr[31:12] <= 20'h0;
        end else if (!stall) begin
            if_id.pc           <= pc_cur;         // address of THIS instruction
            if_id.instr[31:12] <= instr[31:12];
        end

        // opcode + rd: ADDI x0 (NOP) on reset and on flush (wrong path)
        if (rst || flush)
            if_id.instr[11:0] <= 12'h013;
        else if (!stall)
            if_id.instr[11:0] <= instr[11:0];
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

    regfile u_regfile (
        .clk      (clk),
        .we       (wb_we),
        .rs1      (rs1),
        .rs2      (rs2),
        .rd       (wb_rd),
        .rd_data  (wb_data),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .dbg_sel  (dbg_sel),
        .dbg_data (dbg_data)
    );

    // WB -> ID bypass: WB writes the register ID reads in the same cycle
    logic [31:0] id_rs1_val, id_rs2_val;
    assign id_rs1_val = (wb_we && (wb_rd != 5'd0) && (wb_rd == rs1)) ? wb_data : rs1_data;
    assign id_rs2_val = (wb_we && (wb_rd != 5'd0) && (wb_rd == rs2)) ? wb_data : rs2_data;

    // ---------- Hazard unit ----------
    // Load-use: load in EX, its rd is needed by the instruction in ID
    assign stall = (id_ex.wb_sel == 2'd1) && (id_ex.rd != 5'd0) &&
                   ((id_ex.rd == rs1) || (id_ex.rd == rs2));

    // ---------- ID/EX register ----------
    always_ff @(posedge clk) begin
        // data + datapath control: loaded every cycle (don't care in a bubble)
        id_ex.pc        <= if_id.pc;
        id_ex.rs1_data  <= id_rs1_val;
        id_ex.rs2_data  <= id_rs2_val;
        id_ex.imm       <= imm;
        id_ex.rd        <= rd;
        id_ex.rs1       <= rs1;
        id_ex.rs2       <= rs2;
        id_ex.funct3    <= funct3;
        id_ex.alu_op    <= alu_op;
        id_ex.alu_a_sel <= alu_a_sel;
        id_ex.alu_src   <= alu_src;

        // side effects + hazard unit: cleared on reset / bubble
        if (rst || flush || stall) begin
            id_ex.reg_we <= 1'b0;
            id_ex.mem_we <= 1'b0;
            id_ex.branch <= 1'b0;
            id_ex.jump   <= 1'b0;
            id_ex.jalr   <= 1'b0;
            id_ex.wb_sel <= 2'd0;
        end else begin
            id_ex.reg_we <= reg_we;
            id_ex.mem_we <= mem_we;
            id_ex.branch <= branch;
            id_ex.jump   <= jump;
            id_ex.jalr   <= jalr;
            id_ex.wb_sel <= wb_sel;
        end
    end

    // ==================== EX ====================
    // Everything here comes from the ID/EX card
    logic [31:0] alu_a, alu_b;
    logic [31:0] alu_out;
    logic        alu_zero;

    // Forwarding detection: does the instruction in MEM write the register EX reads?
    logic ex_hit_a, ex_hit_b;
    assign ex_hit_a = ex_mem.reg_we && (ex_mem.rd != 5'd0) && (ex_mem.rd == id_ex.rs1);
    assign ex_hit_b = ex_mem.reg_we && (ex_mem.rd != 5'd0) && (ex_mem.rd == id_ex.rs2);

    // Does the instruction in WB write the register EX reads?
    logic wb_hit_a, wb_hit_b;
    assign wb_hit_a = mem_wb.reg_we && (mem_wb.rd != 5'd0) && (mem_wb.rd == id_ex.rs1);
    assign wb_hit_b = mem_wb.reg_we && (mem_wb.rd != 5'd0) && (mem_wb.rd == id_ex.rs2);

    logic [31:0] fwd_a_val;
    always_comb begin
        if (ex_hit_a)      fwd_a_val = ex_mem.alu_out;   // newest write wins
        else if (wb_hit_a) fwd_a_val = wb_data;
        else               fwd_a_val = id_ex.rs1_data;
    end

    logic [31:0] fwd_b_val;
    always_comb begin
        if (ex_hit_b)      fwd_b_val = ex_mem.alu_out;   // newest write wins
        else if (wb_hit_b) fwd_b_val = wb_data;
        else               fwd_b_val = id_ex.rs2_data;
    end

    always_comb begin
        case (id_ex.alu_a_sel)
            2'd1:    alu_a = id_ex.pc;          // AUIPC
            2'd2:    alu_a = 32'h00000000;      // LUI
            default: alu_a = fwd_a_val;
        endcase
    end
    assign alu_b = id_ex.alu_src ? id_ex.imm : fwd_b_val;

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
    assign lt  = $signed(fwd_a_val) < $signed(fwd_b_val);
    assign ltu = fwd_a_val < fwd_b_val;

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

    // ---------- Flush: kill the 2 wrong-path instructions in IF and ID ----------
    assign flush = take_branch | id_ex.jalr | id_ex.jump;

    // ---------- Next PC ----------
    always_comb begin
        case ({id_ex.jalr, id_ex.jump | take_branch})
            2'b10:   pc_next = {alu_out[31:1], 1'b0};  // JALR
            2'b01:   pc_next = pc_target;              // JAL, taken branch
            default: pc_next = pc_plus4;               // keep fetching
        endcase
    end

    // ---------- EX/MEM register ----------
    always_ff @(posedge clk) begin
        if (rst) begin
            ex_mem <= '0;                          // reg_we = mem_we = 0 -> NOP
        end else begin
            // data
            ex_mem.pc_plus4 <= id_ex.pc + 32'd4;   // THIS instruction's pc + 4
            ex_mem.alu_out  <= alu_out;            // born in EX
            ex_mem.rs2_data <= fwd_b_val;          // store data (forwarded)
            // fields
            ex_mem.rd       <= id_ex.rd;
            ex_mem.funct3   <= id_ex.funct3;
            // control
            ex_mem.mem_we   <= id_ex.mem_we;
            ex_mem.wb_sel   <= id_ex.wb_sel;
            ex_mem.reg_we   <= id_ex.reg_we;
        end
    end

    // ==================== MEM ====================
    // Everything here comes from the EX/MEM card

    // ---------- Store: replicate data to every lane ----------
    logic [31:0] st_data;

    always_comb begin
        case (ex_mem.funct3)
            3'b000:  st_data = {4{ex_mem.rs2_data[7:0]}};    // SB
            3'b001:  st_data = {2{ex_mem.rs2_data[15:0]}};   // SH
            default: st_data = ex_mem.rs2_data;              // SW
        endcase
    end

    // ---------- Store: byte enables ----------
    logic [3:0] st_be;

    always_comb begin
        case (ex_mem.funct3)
            3'b000:  st_be = 4'b0001 << ex_mem.alu_out[1:0];         // SB
            3'b001:  st_be = ex_mem.alu_out[1] ? 4'b1100 : 4'b0011;  // SH
            default: st_be = 4'b1111;                                // SW
        endcase
    end

    // ---------- Data memory ----------
    logic [31:0] dmem_rdata;

    dmem u_dmem (
        .clk   (clk),
        .we    (ex_mem.mem_we),
        .be    (st_be),
        .addr  (ex_mem.alu_out),
        .wdata (st_data),
        .rdata (dmem_rdata)
    );

    // ---------- Load: pick the byte ----------
    logic [7:0] ld_byte;

    always_comb begin
        case (ex_mem.alu_out[1:0])
            2'b00:   ld_byte = dmem_rdata[7:0];
            2'b01:   ld_byte = dmem_rdata[15:8];
            2'b10:   ld_byte = dmem_rdata[23:16];
            default: ld_byte = dmem_rdata[31:24];
        endcase
    end

    // ---------- Load: pick the halfword ----------
    logic [15:0] ld_half;

    assign ld_half = ex_mem.alu_out[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];

    // ---------- Load: extend to 32 bits ----------
    logic [31:0] ld_data;

    always_comb begin
        case (ex_mem.funct3)
            3'b000:  ld_data = {{24{ld_byte[7]}}, ld_byte};    // LB
            3'b010:  ld_data = dmem_rdata;                     // LW
            3'b100:  ld_data = {{24{1'b0}}, ld_byte};          // LBU
            3'b001:  ld_data = {{16{ld_half[15]}}, ld_half};   // LH
            3'b101:  ld_data = {{16{1'b0}}, ld_half};          // LHU
            default: ld_data = dmem_rdata;
        endcase
    end

    // ---------- MEM/WB register ----------
    always_ff @(posedge clk) begin
        if (rst) begin
            mem_wb <= '0;                  // reg_we = 0 -> NOP
        end else begin
            // data
            mem_wb.pc_plus4 <= ex_mem.pc_plus4;
            mem_wb.alu_out  <= ex_mem.alu_out;
            mem_wb.ld_data  <= ld_data;
            // fields
            mem_wb.rd       <= ex_mem.rd;
            // control
            mem_wb.wb_sel   <= ex_mem.wb_sel;
            mem_wb.reg_we   <= ex_mem.reg_we;
        end
    end

    // ==================== WB ====================
    // Everything here comes from the MEM/WB card
    assign wb_we = mem_wb.reg_we;
    assign wb_rd = mem_wb.rd;

    always_comb begin
        case (mem_wb.wb_sel)
            2'd0:    wb_data = mem_wb.alu_out;    // R, I, LUI, AUIPC
            2'd1:    wb_data = mem_wb.ld_data;    // loads
            2'd2:    wb_data = mem_wb.pc_plus4;   // JAL, JALR
            default: wb_data = mem_wb.alu_out;    // 2'd3 unused
        endcase
    end

    // ---------- Assertions (simulation only) ----------
    `ifndef SYNTHESIS
        always @(posedge clk) begin
            if (!rst) begin
                // a store has no rd: [11:7] is imm[4:0]
                assert (!(mem_we && reg_we))
                    else begin $display("FAILED: assertion store_writes_reg, pc = 0x%h", if_id.pc); $finish; end
                // stall = load in EX, flush = jump in EX: only one instruction in EX
                assert (!(stall && flush))
                    else begin $display("FAILED: assertion stall_and_flush, pc = 0x%h", id_ex.pc); $finish; end
                // instructions are 4 bytes; imem ignores addr[1:0], so a bad jump would fail silently
                assert (pc_cur[1:0] == 2'b00)
                    else begin $display("FAILED: assertion pc_misaligned, pc = 0x%h", pc_cur); $finish; end
                // x on a control bit = unconnected wire or missing reset
                assert (!$isunknown(id_ex.reg_we))
                    else begin $display("FAILED: assertion reg_we_unknown, pc = 0x%h", id_ex.pc); $finish; end
            end
        end
    `endif

endmodule
