#!/usr/bin/env python3
"""RV32I reference model (instruction-set simulator) for riscv-cpu."""

MASK = 0xFFFFFFFF          # registers hold 0 .. 0xFFFFFFFF (unsigned)


def sext(value, bits):
    """Sign-extend the low `bits` bits of value: 0xFFD, 12 -> -3."""
    value &= (1 << bits) - 1          # keep only the low bits
    if value >> (bits - 1):           # sign bit set?
        return value - (1 << bits)
    return value

def decode(instr):
    """Split an instruction into its fields (like instr[11:7] in the RTL)."""
    opcode = instr & 0x7F                 # instr[6:0]
    rd     = (instr >> 7) & 0x1F          # instr[11:7]
    funct3 = (instr >> 12) & 0x7          # instr[14:12]
    rs1    = (instr >> 15) & 0x1F          # instr[19:15]
    rs2    = (instr >> 20) & 0x1F          # instr[24:20]
    funct7 = instr >> 25                  # instr[31:25]
    return opcode, rd, funct3, rs1, rs2, funct7

def immediates(instr):
    """All five immediate formats (like immgen.sv); the decoder picks the one it needs."""
    imm_i = sext(instr >> 20, 12)                                         # [31:20]
    imm_s = sext(((instr >> 25) << 5) | (instr >> 7) & 0x1F, 12)                         # [31:25] [11:7]
    imm_b = sext(((instr >> 31) << 12) | (((instr >> 7) & 1) << 11) |
                 (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1), 13)
    imm_u = instr & 0xFFFFF000                                                    # [31:12], low 12 bits = 0
    imm_j = sext(((instr >> 31) << 20) | (((instr >> 12) & 0xFF) << 12) |
                 (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1), 21)
    return imm_i, imm_s, imm_b, imm_u, imm_j

def alu(funct3, alt, a, b):
    """R-type and I-type ALU. a, b are unsigned 32-bit; alt = instr[30] (SUB / SRA)."""
    sh = b & 0x1F                                       # shift amount = low 5 bits
    if   funct3 == 0: r = a - b if alt else a + b       # ADD / SUB
    elif funct3 == 1: r = a << sh                       # SLL
    elif funct3 == 2: r = 1 if sext(a, 32) < sext(b,32) else 0      # SLT  (signed)
    elif funct3 == 3: r = 1 if (a < b) else 0                       # SLTU (unsigned)
    elif funct3 == 4: r = a ^ b                       # XOR
    elif funct3 == 5: r = (sext(a, 32) >> sh) if alt else a >> sh   # SRA / SRL
    elif funct3 == 6: r = a | b                         # OR
    else:             r = a & b                         # AND
    return r & MASK

if __name__ == "__main__":
    tests = [                                           # (funct3, alt, a, b, expected)
        (0, 1, 5, 8, 0xFFFFFFFD),                       # SUB:  5 - 8
        (1, 0, 1, 33, 0x00000002),                      # SLL:  only b[4:0] = 1 counts
        (2, 0, 0xFFFFFFFD, 5, 1),                       # SLT:  -3 < 5
        (3, 0, 0xFFFFFFFD, 5, 0),                       # SLTU: 0xFFFFFFFD < 5? no
        (4, 0, 0xF0F0, 0x0FF0, 0xFF00),                 # XOR
        (5, 1, 0x80000000, 4, 0xF8000000),              # SRA:  sign bit copied
        (5, 0, 0x80000000, 4, 0x08000000),              # SRL:  zeros shifted in
    ]
    for f3, alt, a, b, exp in tests:
        got = alu(f3, alt, a, b)
        print(f"f3={f3} alt={alt}  got {got:08X}  {'ok' if got == exp else f'WRONG, exp {exp:08X}'}")