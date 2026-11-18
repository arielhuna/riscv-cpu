`timescale 1ns / 1ps
package pipe_pkg;
    import alu_pkg::*;   // for alu_op_t

    // IF/ID: fetch -> decode
    typedef struct packed {
        logic [31:0] pc;      // address of THIS instruction
        logic [31:0] instr;
    } if_id_t;

    // ID/EX: decode -> execute
    typedef struct packed {
        // data
        logic [31:0] pc;
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic [31:0] imm;
        // instruction fields still needed later
        logic [4:0]  rd;
        logic [4:0]  rs1;     // for forwarding (lesson 27)
        logic [4:0]  rs2;
        logic [2:0]  funct3;
        // control (from u_control in ID)
        alu_op_t     alu_op;
        logic [1:0]  alu_a_sel;
        logic [1:0]  wb_sel;
        logic        alu_src;
        logic        reg_we;
        logic        mem_we;
        logic        branch;
        logic        jump;
        logic        jalr;
    } id_ex_t;

    // EX/MEM: execute -> memory
    typedef struct packed {
        // data
        logic [31:0] pc_plus4;   // id_ex.pc + 4 (JAL/JALR link), NOT IF's pc_plus4
        logic [31:0] alu_out;    // result, or load/store address
        logic [31:0] rs2_data;   // store data
        // fields
        logic [4:0]  rd;
        logic [2:0]  funct3;     // load/store width
        // control
        logic        mem_we;     // used in MEM
        logic [1:0]  wb_sel;     // used in WB
        logic        reg_we;     // used in WB
    } ex_mem_t;

    // MEM/WB: memory -> writeback
    typedef struct packed {
        // data
        logic [31:0] pc_plus4;   // wb_sel = 2 (JAL/JALR)
        logic [31:0] alu_out;    // wb_sel = 0 (R, I, LUI, AUIPC)
        logic [31:0] ld_data;    // wb_sel = 1 (loads), born in MEM
        // fields
        logic [4:0]  rd;
        // control
        logic [1:0]  wb_sel;
        logic        reg_we;
    } mem_wb_t;

endpackage