`timescale 1ns / 1ps

module control import alu_pkg::*, rv32i_pkg::*; (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic       instr30,
    output alu_op_t    alu_op,
    output logic       alu_src,
    output logic [1:0] alu_a_sel,
    output logic [1:0] wb_sel,
    output logic       reg_we,
    output logic       mem_we,
    output logic       branch,
    output logic       jump,
    output logic       jalr
);

    always_comb begin
        // Safe defaults: unknown instruction = NOP
        alu_op  = ALU_ADD;
        alu_src = 1'b0;
        alu_a_sel = 2'd0;
        wb_sel  = 2'd0;
        reg_we  = 1'b0;
        mem_we  = 1'b0;
        branch  = 1'b0;
        jump    = 1'b0;
        jalr    = 1'b0;

        case (opcode)
            OP_R: begin
                alu_op = alu_op_t'({instr30, funct3});
                reg_we = 1'b1;
            end

            OP_LOAD: begin
                alu_op  = ALU_ADD;
                alu_src = 1'b1;
                wb_sel  = 2'd1;
                reg_we  = 1'b1;
            end

            OP_IMM: begin
                if (funct3 == 3'b101) // SRAI or SRLI
                    alu_op = alu_op_t'({instr30, funct3});
                else // ADDI, SLTI, SLTIU, ANDI, ORI, XORI, SLLI
                    alu_op = alu_op_t'({1'b0, funct3});
                alu_src = 1'b1; 
                wb_sel  = 2'd0;
                reg_we  = 1'b1;
            end

            OP_STORE: begin
                alu_op  = ALU_ADD;
                alu_src = 1'b1;
                reg_we = 1'b0;
                mem_we  = 1'b1;
            end
            
            OP_BRANCH: begin
                alu_op  = ALU_SUB;
                alu_src = 1'b0;
                reg_we = 1'b0;
                mem_we  = 1'b0;
                branch  = 1'b1;
            end

            OP_JAL: begin
                reg_we = 1'b1;
                jump   = 1'b1;
                wb_sel = 2'd2;
            end

            OP_JALR: begin
                alu_op  = ALU_ADD;
                alu_src = 1'b1;
                wb_sel = 2'd2;
                reg_we = 1'b1;
                jalr   = 1'b1;
            end
            
            OP_LUI: begin
                alu_op    = ALU_ADD;
                alu_src   = 1'b1;
                reg_we    = 1'b1;
                alu_a_sel = 2'd2;
                wb_sel    = 2'b0;
            end

            OP_AUIPC: begin
                alu_op    = ALU_ADD;
                alu_src   = 1'b1;
                reg_we    = 1'b1;
                alu_a_sel = 2'd1;
                wb_sel    = 2'b0;
            end

            default: ;
        endcase
    end

endmodule