`timescale 1ns / 1ps
module immgen
    import rv32i_pkg::*;
(
    input  logic [31:0] instr,
    output logic [31:0] imm
);
    always_comb begin : immgen_comb
        case (instr[6:0])
            OP_IMM, OP_LOAD, OP_JALR: begin  // I-type
                imm = {{20{instr[31]}}, instr[31:20]};
            end
            OP_STORE: begin // S-type
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end
            OP_BRANCH: begin // B-type
                imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            end
            OP_LUI, OP_AUIPC: begin // U-type
                imm = {instr[31:12], 12'b0};
            end
            OP_JAL: begin // J-type
                imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
            end
            default: begin // For R-type and other instructions, immediate is not used
                imm = 32'b0;
            end
        endcase
    end
endmodule
