#!/usr/bin/env python3
"""
rvasm.py - tiny RV32I assembler for the riscv-cpu project.

Usage:
    python rvasm.py programs/test_mem.s                  -> writes programs/test_mem.hex
    python rvasm.py programs/test_mem.s -o out.hex       -> custom output
    python rvasm.py -e "SW x5, 4(x6)"                    -> encode one line, print it

Source format:
    - one instruction per line, '#' or '//' starts a comment
    - labels:  loop:   (alone or before an instruction)
    - registers: x0..x31 or ABI names (zero, ra, sp, t0, a0, s0/fp ...)
    - numbers: decimal, negative, 0x.., 0b..
    - case-insensitive (ADDI == addi)

Output (file and screen are identical, ready to paste into a .hex file):
    00700293  // 0x00  ADDI x5, x0, 7
$readmemh ignores everything after //.  Use --plain for bare words only.

Supported: all RV32I base instructions (R, I, loads, stores, branches,
JAL, JALR, LUI, AUIPC) + pseudos: nop, mv, li, j, jr, ret, not, neg,
seqz, snez, sltz, sgtz, beqz, bnez, bltz, bgez, blez, bgtz,
bgt, ble, bgtu, bleu.
"""

import argparse
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------- registers
ABI = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7, "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15, "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23, "s8": 24,
    "s9": 25, "s10": 26, "s11": 27, "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}


class AsmError(Exception):
    pass


def reg(tok):
    t = tok.strip().lower()
    if re.fullmatch(r"x([0-9]|[12][0-9]|3[01])", t):
        return int(t[1:])
    if t in ABI:
        return ABI[t]
    raise AsmError(f"bad register '{tok}'")


def num(tok):
    try:
        return int(tok.strip().replace("_", ""), 0)
    except ValueError:
        raise AsmError(f"bad number '{tok}'")


def check_range(val, bits, signed, what):
    if signed:
        lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    else:
        lo, hi = 0, (1 << bits) - 1
    if not lo <= val <= hi:
        raise AsmError(f"{what} {val} out of range [{lo}, {hi}]")


# ---------------------------------------------------------------- tables
# R-type: funct7, funct3
R_OPS = {
    "add": (0x00, 0), "sub": (0x20, 0), "sll": (0x00, 1), "slt": (0x00, 2),
    "sltu": (0x00, 3), "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5),
    "or": (0x00, 6), "and": (0x00, 7),
}
# I-type ALU: funct3
I_OPS = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
# shift-immediate: funct7, funct3
SH_OPS = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
LOAD_OPS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORE_OPS = {"sb": 0, "sh": 1, "sw": 2}
BR_OPS = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}

OP_R, OP_IMM, OP_LOAD, OP_STORE = 0b0110011, 0b0010011, 0b0000011, 0b0100011
OP_BRANCH, OP_JALR, OP_JAL = 0b1100011, 0b1100111, 0b1101111
OP_LUI, OP_AUIPC = 0b0110111, 0b0010111


# ---------------------------------------------------------------- encoders
def enc_r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_i(imm, rs1, f3, rd, op):
    check_range(imm, 12, True, "I-imm")
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3, op):
    check_range(imm, 12, True, "S-imm")
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op


def enc_b(off, rs2, rs1, f3, op):
    if off % 2:
        raise AsmError(f"branch offset {off} is odd")
    check_range(off, 13, True, "branch offset")
    o = off & 0x1FFF
    return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) \
        | (f3 << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | op


def enc_u(imm20, rd, op):
    check_range(imm20, 20, False, "U-imm (upper 20 bits)")
    return (imm20 << 12) | (rd << 7) | op


def enc_j(off, rd, op):
    if off % 2:
        raise AsmError(f"jump offset {off} is odd")
    check_range(off, 21, True, "jump offset")
    o = off & 0x1FFFFF
    return (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) \
        | (((o >> 12) & 0xFF) << 12) | (rd << 7) | op


# ---------------------------------------------------------------- parsing
def split_args(s):
    return [a.strip() for a in s.split(",")] if s.strip() else []


def mem_operand(tok):
    """'4(x6)' -> (4, 6);  '(x6)' -> (0, 6)"""
    m = re.fullmatch(r"\s*([^()]*)\(\s*([^()]+?)\s*\)\s*", tok)
    if not m:
        raise AsmError(f"bad memory operand '{tok}', expected imm(reg)")
    off = num(m.group(1)) if m.group(1).strip() else 0
    return off, reg(m.group(2))


def expand_li(rd, val):
    """li -> 1 or 2 real instructions"""
    val &= 0xFFFFFFFF
    sval = val - (1 << 32) if val & 0x80000000 else val
    if -2048 <= sval <= 2047:
        return [("addi", [rd, "x0", str(sval)])]
    lo = val & 0xFFF
    if lo >= 0x800:
        lo -= 0x1000
    hi = ((val - lo) >> 12) & 0xFFFFF
    out = [("lui", [rd, str(hi)])]
    if lo:
        out.append(("addi", [rd, rd, str(lo)]))
    return out


def expand(mn, args):
    """pseudo-instructions -> list of (mnemonic, args) real instructions"""
    a = args
    if mn == "nop":
        return [("addi", ["x0", "x0", "0"])]
    if mn == "mv":
        return [("addi", [a[0], a[1], "0"])]
    if mn == "not":
        return [("xori", [a[0], a[1], "-1"])]
    if mn == "neg":
        return [("sub", [a[0], "x0", a[1]])]
    if mn == "li":
        return expand_li(a[0], num(a[1]))
    if mn == "j":
        return [("jal", ["x0", a[0]])]
    if mn == "jr":
        return [("jalr", ["x0", f"0({a[0]})"])]
    if mn == "ret":
        return [("jalr", ["x0", "0(ra)"])]
    if mn == "beqz":
        return [("beq", [a[0], "x0", a[1]])]
    if mn == "bnez":
        return [("bne", [a[0], "x0", a[1]])]
    if mn == "bgt":
        return [("blt", [a[1], a[0], a[2]])]
    if mn == "ble":
        return [("bge", [a[1], a[0], a[2]])]
    if mn == "bgtu":
        return [("bltu", [a[1], a[0], a[2]])]
    if mn == "bleu":
        return [("bgeu", [a[1], a[0], a[2]])]
    if mn == "seqz":
        return [("sltiu", [a[0], a[1], "1"])]
    if mn == "snez":
        return [("sltu", [a[0], "x0", a[1]])]
    if mn == "sltz":
        return [("slt", [a[0], a[1], "x0"])]
    if mn == "sgtz":
        return [("slt", [a[0], "x0", a[1]])]
    if mn == "bltz":
        return [("blt", [a[0], "x0", a[1]])]
    if mn == "bgez":
        return [("bge", [a[0], "x0", a[1]])]
    if mn == "blez":
        return [("bge", ["x0", a[0], a[1]])]
    if mn == "bgtz":
        return [("blt", ["x0", a[0], a[1]])]
    if mn == "jal" and len(a) == 1:
        return [("jal", ["ra", a[0]])]
    if mn == "jalr" and len(a) == 1:
        return [("jalr", ["ra", f"0({a[0]})"])]
    return [(mn, a)]


def target(tok, labels, pc):
    t = tok.strip()
    if t in labels:
        return labels[t] - pc
    try:
        return num(t)  # raw numeric offset
    except AsmError:
        raise AsmError(f"unknown label '{t}'")


def need(args, n, mn):
    if len(args) != n:
        raise AsmError(f"'{mn}' expects {n} operands, got {len(args)}")


def encode(mn, args, pc, labels):
    if mn in R_OPS:
        need(args, 3, mn)
        f7, f3 = R_OPS[mn]
        return enc_r(f7, reg(args[2]), reg(args[1]), f3, reg(args[0]), OP_R)
    if mn in I_OPS:
        need(args, 3, mn)
        return enc_i(num(args[2]), reg(args[1]), I_OPS[mn], reg(args[0]), OP_IMM)
    if mn in SH_OPS:
        need(args, 3, mn)
        f7, f3 = SH_OPS[mn]
        sh = num(args[2])
        check_range(sh, 5, False, "shift amount")
        return enc_r(f7, sh, reg(args[1]), f3, reg(args[0]), OP_IMM)
    if mn in LOAD_OPS:
        need(args, 2, mn)
        off, rs1 = mem_operand(args[1])
        return enc_i(off, rs1, LOAD_OPS[mn], reg(args[0]), OP_LOAD)
    if mn in STORE_OPS:
        need(args, 2, mn)
        off, rs1 = mem_operand(args[1])
        return enc_s(off, reg(args[0]), rs1, STORE_OPS[mn], OP_STORE)
    if mn in BR_OPS:
        need(args, 3, mn)
        return enc_b(target(args[2], labels, pc), reg(args[1]), reg(args[0]), BR_OPS[mn], OP_BRANCH)
    if mn == "jal":
        need(args, 2, mn)
        return enc_j(target(args[1], labels, pc), reg(args[0]), OP_JAL)
    if mn == "jalr":
        if len(args) == 3:  # jalr rd, rs1, imm
            return enc_i(num(args[2]), reg(args[1]), 0, reg(args[0]), OP_JALR)
        need(args, 2, mn)   # jalr rd, imm(rs1)
        off, rs1 = mem_operand(args[1])
        return enc_i(off, rs1, 0, reg(args[0]), OP_JALR)
    if mn == "lui":
        need(args, 2, mn)
        return enc_u(num(args[1]), reg(args[0]), OP_LUI)
    if mn == "auipc":
        need(args, 2, mn)
        return enc_u(num(args[1]), reg(args[0]), OP_AUIPC)
    raise AsmError(f"unknown instruction '{mn}'")


def strip_comment(line):
    return re.split(r"#|//", line, maxsplit=1)[0]


def assemble(text):
    """returns list of (pc, word, source_text, lineno)"""
    # pass 1: labels and instruction list
    labels, items, pc = {}, [], 0
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = strip_comment(raw).strip()
        while True:
            m = re.match(r"([A-Za-z_.][\w.]*)\s*:\s*", line)
            if not m:
                break
            name = m.group(1)
            if name in labels:
                raise AsmError(f"line {lineno}: duplicate label '{name}'")
            labels[name] = pc
            line = line[m.end():]
        if not line:
            continue
        parts = line.split(None, 1)
        mn = parts[0].lower()
        args = split_args(parts[1] if len(parts) > 1 else "")
        try:
            real = expand(mn, args)
        except (AsmError, IndexError) as e:
            raise AsmError(f"line {lineno}: {e or 'missing operand'} -> {raw.strip()}")
        for i, (rmn, rargs) in enumerate(real):
            items.append((pc, rmn, rargs, raw.strip() if i == 0 else "  (cont.)", lineno))
            pc += 4
    # pass 2: encode
    out = []
    for pc, mn, args, src, lineno in items:
        try:
            word = encode(mn, args, pc, labels)
        except (AsmError, IndexError) as e:
            raise AsmError(f"line {lineno}: {e or 'missing operand'} -> {src}")
        out.append((pc, word, src, lineno))
    return out


def fmt(pc, w, src, plain):
    if plain:
        return f"{w:08X}\n"
    src = re.sub(r"\s+", " ", strip_comment(src).strip())  # one clean line
    return f"{w:08X}  // 0x{pc:02X}  {src}\n"


def main():
    ap = argparse.ArgumentParser(description="tiny RV32I assembler")
    ap.add_argument("src", nargs="?", help="assembly file (.s)")
    ap.add_argument("-o", "--out", help="output .hex (default: same name as src)")
    ap.add_argument("-e", "--expr", help="encode a single line and print it")
    ap.add_argument("--plain", action="store_true", help="hex words only, no comments")
    a = ap.parse_args()

    try:
        if a.expr:
            print("".join(fmt(pc, w, s, a.plain) for pc, w, s, _ in assemble(a.expr)), end="")
            return
        if not a.src:
            ap.error("give a source file or -e")
        src = Path(a.src)
        res = assemble(src.read_text(encoding="utf-8"))
    except AsmError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    out = Path(a.out) if a.out else src.with_suffix(".hex")
    text = "".join(fmt(pc, w, s, a.plain) for pc, w, s, _ in res)
    out.write_text(text, encoding="utf-8")
    print(text, end="")
    print(f"// -> {out}  ({len(res)} words)")


if __name__ == "__main__":
    main()
