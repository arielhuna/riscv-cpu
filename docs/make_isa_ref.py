#!/usr/bin/env python3
"""
make_isa_ref.py - build docs/rv32i_reference.pdf

Instruction reference for this core: every RV32I instruction it runs, its
encoding, what it does, and the control signals rtl/control.sv sets for it.
Machine-code examples are produced by ../rvasm.py, so they always match the
assembler used for the test programs.

    python docs/make_isa_ref.py            # writes .html and .pdf
    python docs/make_isa_ref.py --html     # .html only (open it, Ctrl+P)

The PDF step needs Chrome or Edge (headless print). Edit the tables below
when the CPU changes (new opcode, new control signal), then re-run.
"""

import argparse
import datetime
import html
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
RVASM = ROOT / "rvasm.py"

# ---------------------------------------------------------------------------
# data
# ---------------------------------------------------------------------------

FORMATS = {
    #      fields: (label, width in bits)
    "R": [("funct7", 7), ("rs2", 5), ("rs1", 5), ("funct3", 3), ("rd", 5), ("opcode", 7)],
    "I": [("imm[11:0]", 12), ("rs1", 5), ("funct3", 3), ("rd", 5), ("opcode", 7)],
    "S": [("imm[11:5]", 7), ("rs2", 5), ("rs1", 5), ("funct3", 3), ("imm[4:0]", 5), ("opcode", 7)],
    "B": [("imm[12|10:5]", 7), ("rs2", 5), ("rs1", 5), ("funct3", 3), ("imm[4:1|11]", 5), ("opcode", 7)],
    "U": [("imm[31:12]", 20), ("rd", 5), ("opcode", 7)],
    "J": [("imm[20|10:1|11|19:12]", 20), ("rd", 5), ("opcode", 7)],
}

IMMGEN = [
    ("I", "ADDI…, loads, JALR", "{{20{i[31]}}, i[31:20]}", "−2048 … 2047"),
    ("S", "stores", "{{20{i[31]}}, i[31:25], i[11:7]}", "−2048 … 2047"),
    ("B", "branches", "{{20{i[31]}}, i[7], i[30:25], i[11:8], 1'b0}", "±4 KiB, even"),
    ("U", "LUI, AUIPC", "{i[31:12], 12'b0}", "upper 20 bits"),
    ("J", "JAL", "{{12{i[31]}}, i[19:12], i[20], i[30:21], 1'b0}", "±1 MiB, even"),
    ("R", "R-type", "32'b0 (unused)", "—"),
]

# control signal values per opcode, straight from rtl/control.sv
# alu_op None = per-instruction column; "x" = not used
GROUPS = [
    dict(
        key="R", title="Register–register", fmt="R", opcode="0110011", pkg="OP_R",
        ctrl=dict(alu_op=None, alu_src="0", alu_a_sel="0", wb_sel="0", reg_we="1",
                  mem_we="0", branch="0", jump="0", jalr="0"),
        note="alu_op = {instr[30], funct3}: the ALU code is the instruction's own bits.",
        tb="tb_cpu (test_ri), tb_alu",
        rows=[
            ("ADD",  "ADD rd, rs1, rs2",  "rd = rs1 + rs2",                 "000", "0000000", "ALU_ADD",  "ADD x5, x6, x7"),
            ("SUB",  "SUB rd, rs1, rs2",  "rd = rs1 − rs2",                 "000", "0100000", "ALU_SUB",  "SUB x5, x6, x7"),
            ("SLL",  "SLL rd, rs1, rs2",  "rd = rs1 << rs2[4:0]",           "001", "0000000", "ALU_SLL",  "SLL x5, x6, x7"),
            ("SLT",  "SLT rd, rs1, rs2",  "rd = (rs1 <ₛ rs2) ? 1 : 0",      "010", "0000000", "ALU_SLT",  "SLT x5, x6, x7"),
            ("SLTU", "SLTU rd, rs1, rs2", "rd = (rs1 <ᵤ rs2) ? 1 : 0",      "011", "0000000", "ALU_SLTU", "SLTU x5, x6, x7"),
            ("XOR",  "XOR rd, rs1, rs2",  "rd = rs1 ^ rs2",                 "100", "0000000", "ALU_XOR",  "XOR x5, x6, x7"),
            ("SRL",  "SRL rd, rs1, rs2",  "rd = rs1 >> rs2[4:0]  (zeros in)", "101", "0000000", "ALU_SRL", "SRL x5, x6, x7"),
            ("SRA",  "SRA rd, rs1, rs2",  "rd = rs1 >>> rs2[4:0] (sign in)", "101", "0100000", "ALU_SRA",  "SRA x5, x6, x7"),
            ("OR",   "OR rd, rs1, rs2",   "rd = rs1 | rs2",                 "110", "0000000", "ALU_OR",   "OR x5, x6, x7"),
            ("AND",  "AND rd, rs1, rs2",  "rd = rs1 & rs2",                 "111", "0000000", "ALU_AND",  "AND x5, x6, x7"),
        ],
    ),
    dict(
        key="I", title="Register–immediate", fmt="I", opcode="0010011", pkg="OP_IMM",
        ctrl=dict(alu_op=None, alu_src="1", alu_a_sel="0", wb_sel="0", reg_we="1",
                  mem_we="0", branch="0", jump="0", jalr="0"),
        note="alu_op = {1'b0, funct3}, except funct3 = 101 (shift right) which keeps instr[30]. "
             "Without that rule a negative ADDI (imm bit 10 = 1 → instr[30] = 1) would silently become SUB.",
        tb="tb_cpu (test_ri)",
        rows=[
            ("ADDI",  "ADDI rd, rs1, imm",   "rd = rs1 + imm",                "000", "—",       "ALU_ADD",  "ADDI x5, x6, -4"),
            ("SLTI",  "SLTI rd, rs1, imm",   "rd = (rs1 <ₛ imm) ? 1 : 0",     "010", "—",       "ALU_SLT",  "SLTI x5, x6, 10"),
            ("SLTIU", "SLTIU rd, rs1, imm",  "rd = (rs1 <ᵤ imm) ? 1 : 0",     "011", "—",       "ALU_SLTU", "SLTIU x5, x6, 10"),
            ("XORI",  "XORI rd, rs1, imm",   "rd = rs1 ^ imm",                "100", "—",       "ALU_XOR",  "XORI x5, x6, -1"),
            ("ORI",   "ORI rd, rs1, imm",    "rd = rs1 | imm",                "110", "—",       "ALU_OR",   "ORI x5, x6, 0xF0"),
            ("ANDI",  "ANDI rd, rs1, imm",   "rd = rs1 & imm",                "111", "—",       "ALU_AND",  "ANDI x5, x6, 0xFF"),
            ("SLLI",  "SLLI rd, rs1, shamt", "rd = rs1 << shamt",             "001", "0000000", "ALU_SLL",  "SLLI x5, x6, 4"),
            ("SRLI",  "SRLI rd, rs1, shamt", "rd = rs1 >> shamt  (zeros in)", "101", "0000000", "ALU_SRL",  "SRLI x5, x6, 4"),
            ("SRAI",  "SRAI rd, rs1, shamt", "rd = rs1 >>> shamt (sign in)",  "101", "0100000", "ALU_SRA",  "SRAI x5, x6, 4"),
        ],
    ),
    dict(
        key="L", title="Loads", fmt="I", opcode="0000011", pkg="OP_LOAD",
        ctrl=dict(alu_op="ALU_ADD", alu_src="1", alu_a_sel="0", wb_sel="1", reg_we="1",
                  mem_we="0", branch="0", jump="0", jalr="0"),
        note="The ALU computes the byte address rs1 + imm. funct3 bit 2 = unsigned, bits 1:0 = size. "
             "Accesses must stay inside one aligned word.",
        tb="tb_cpu_ldst (test_ldst), tb_cpu_mem",
        rows=[
            ("LB",  "LB rd, imm(rs1)",  "rd = sext(M[rs1+imm][7:0])",  "000", "—", "ALU_ADD", "LB x5, 3(x6)"),
            ("LH",  "LH rd, imm(rs1)",  "rd = sext(M[rs1+imm][15:0])", "001", "—", "ALU_ADD", "LH x5, 2(x6)"),
            ("LW",  "LW rd, imm(rs1)",  "rd = M[rs1+imm][31:0]",       "010", "—", "ALU_ADD", "LW x5, 8(x6)"),
            ("LBU", "LBU rd, imm(rs1)", "rd = zext(M[rs1+imm][7:0])",  "100", "—", "ALU_ADD", "LBU x5, 3(x6)"),
            ("LHU", "LHU rd, imm(rs1)", "rd = zext(M[rs1+imm][15:0])", "101", "—", "ALU_ADD", "LHU x5, 2(x6)"),
        ],
    ),
    dict(
        key="S", title="Stores", fmt="S", opcode="0100011", pkg="OP_STORE",
        ctrl=dict(alu_op="ALU_ADD", alu_src="1", alu_a_sel="0", wb_sel="x", reg_we="0",
                  mem_we="1", branch="0", jump="0", jalr="0"),
        note="rs2's low byte / half is replicated to every lane; the byte enables (be) pick the lane by addr[1:0].",
        tb="tb_cpu_ldst (test_ldst), tb_cpu_mem",
        rows=[
            ("SB", "SB rs2, imm(rs1)", "M[rs1+imm][7:0]  = rs2[7:0]",  "000", "—", "ALU_ADD", "SB x5, 3(x6)"),
            ("SH", "SH rs2, imm(rs1)", "M[rs1+imm][15:0] = rs2[15:0]", "001", "—", "ALU_ADD", "SH x5, 2(x6)"),
            ("SW", "SW rs2, imm(rs1)", "M[rs1+imm][31:0] = rs2",       "010", "—", "ALU_ADD", "SW x5, 8(x6)"),
        ],
    ),
    dict(
        key="B", title="Branches", fmt="B", opcode="1100011", pkg="OP_BRANCH",
        ctrl=dict(alu_op="ALU_SUB", alu_src="0", alu_a_sel="0", wb_sel="x", reg_we="0",
                  mem_we="0", branch="1", jump="0", jalr="0"),
        note="Target = pc + imm, relative to the branch itself (not pc + 4). "
             "take_branch = branch & br_cond, computed in cpu.sv from alu_zero, lt, ltu.",
        tb="tb_cpu_sum (BNE), tb_cpu_br (BLT/BLTU/BGE/BGEU)",
        rows=[
            ("BEQ",  "BEQ rs1, rs2, label",  "if (rs1 == rs2) pc += imm",  "000", "—", "alu_zero",  "BEQ x5, x6, -8"),
            ("BNE",  "BNE rs1, rs2, label",  "if (rs1 != rs2) pc += imm",  "001", "—", "~alu_zero", "BNE x5, x6, -8"),
            ("BLT",  "BLT rs1, rs2, label",  "if (rs1 <ₛ rs2) pc += imm",  "100", "—", "lt",        "BLT x5, x6, -8"),
            ("BGE",  "BGE rs1, rs2, label",  "if (rs1 ≥ₛ rs2) pc += imm",  "101", "—", "~lt",       "BGE x5, x6, -8"),
            ("BLTU", "BLTU rs1, rs2, label", "if (rs1 <ᵤ rs2) pc += imm",  "110", "—", "ltu",       "BLTU x5, x6, -8"),
            ("BGEU", "BGEU rs1, rs2, label", "if (rs1 ≥ᵤ rs2) pc += imm",  "111", "—", "~ltu",      "BGEU x5, x6, -8"),
        ],
    ),
    dict(
        key="JAL", title="Jump and link", fmt="J", opcode="1101111", pkg="OP_JAL",
        ctrl=dict(alu_op="x", alu_src="x", alu_a_sel="x", wb_sel="2", reg_we="1",
                  mem_we="0", branch="0", jump="1", jalr="0"),
        note="pc + imm goes to the PC (pc_target adder), pc + 4 goes to rd. The ALU is idle. "
             "JAL x0, label is a plain jump; done: JAL x0, done halts a test program.",
        tb="tb_cpu_call (test_call)",
        rows=[
            ("JAL", "JAL rd, label", "rd = pc + 4;  pc += imm", "—", "—", "—", "JAL x1, 16"),
        ],
    ),
    dict(
        key="JALR", title="Jump and link register", fmt="I", opcode="1100111", pkg="OP_JALR",
        ctrl=dict(alu_op="ALU_ADD", alu_src="1", alu_a_sel="0", wb_sel="2", reg_we="1",
                  mem_we="0", branch="0", jump="0", jalr="1"),
        note="The ALU computes rs1 + imm; bit 0 is cleared before it reaches the PC. "
             "JALR x0, 0(ra) is the function return (ret).",
        tb="tb_cpu_call (test_call)",
        rows=[
            ("JALR", "JALR rd, imm(rs1)", "rd = pc + 4;  pc = (rs1 + imm) & ~1", "000", "—", "ALU_ADD", "JALR x0, 0(x1)"),
        ],
    ),
    dict(
        key="U", title="Upper immediate", fmt="U", opcode=None, pkg=None,
        ctrl=dict(alu_op="ALU_ADD", alu_src="1", alu_a_sel=None, wb_sel="0", reg_we="1",
                  mem_we="0", branch="0", jump="0", jalr="0"),
        note="Both reuse the ALU with an ADD; only the A input changes (alu_a_sel). "
             "LUI + ADDI together load any 32-bit constant (that is what the li pseudo does).",
        tb="tb_cpu_br (test_br)",
        rows=[
            ("LUI",   "LUI rd, imm20",   "rd = imm20 << 12",       "0110111", "2 (zero)",   "ALU_ADD", "LUI x5, 0x12345"),
            ("AUIPC", "AUIPC rd, imm20", "rd = pc + (imm20 << 12)", "0010111", "1 (pc_cur)", "ALU_ADD", "AUIPC x6, 0x1"),
        ],
    ),
]

SIGNALS = [
    ("alu_op", "4", "ALU operation (alu_op_t)"),
    ("alu_src", "1", "ALU B: 0 = rs2_data, 1 = imm"),
    ("alu_a_sel", "2", "ALU A: 0 = rs1_data, 1 = pc_cur, 2 = 0"),
    ("wb_sel", "2", "rd source: 0 ALU, 1 load, 2 pc + 4"),
    ("reg_we", "1", "Write rd on the clock edge (never x0)"),
    ("mem_we", "1", "Write dmem on the clock edge, lanes = be"),
    ("branch", "1", "Branch: take_branch = branch & br_cond"),
    ("jump", "1", "JAL: next PC = pc_target"),
    ("jalr", "1", "JALR: next PC = {alu_out[31:1], 1'b0}"),
]

ALU_OPS = [
    ("ALU_ADD", "0000", "a + b"), ("ALU_SUB", "1000", "a − b"),
    ("ALU_SLL", "0001", "a << b[4:0]"), ("ALU_SLT", "0010", "a <ₛ b"),
    ("ALU_SLTU", "0011", "a <ᵤ b"), ("ALU_XOR", "0100", "a ^ b"),
    ("ALU_SRL", "0101", "a >> b[4:0]"), ("ALU_SRA", "1101", "a >>> b[4:0]"),
    ("ALU_OR", "0110", "a | b"), ("ALU_AND", "0111", "a & b"),
]

ABI = [
    ("x0", "zero", "hard-wired 0"), ("x1", "ra", "return address"),
    ("x2", "sp", "stack pointer"), ("x3", "gp", "global pointer"),
    ("x4", "tp", "thread pointer"), ("x5–x7", "t0–t2", "temporaries"),
    ("x8", "s0 / fp", "saved / frame ptr"), ("x9", "s1", "saved"),
    ("x10–x11", "a0–a1", "args / return values"), ("x12–x17", "a2–a7", "arguments"),
    ("x18–x27", "s2–s11", "saved"), ("x28–x31", "t3–t6", "temporaries"),
]

PSEUDOS = [
    ("nop", "ADDI x0, x0, 0"), ("mv rd, rs", "ADDI rd, rs, 0"),
    ("li rd, imm", "ADDI, or LUI + ADDI"), ("not rd, rs", "XORI rd, rs, -1"),
    ("neg rd, rs", "SUB rd, x0, rs"), ("j label", "JAL x0, label"),
    ("jal label", "JAL ra, label"), ("jr rs", "JALR x0, 0(rs)"),
    ("ret", "JALR x0, 0(ra)"), ("seqz rd, rs", "SLTIU rd, rs, 1"),
    ("snez rd, rs", "SLTU rd, x0, rs"), ("sltz / sgtz", "SLT with x0"),
    ("beqz / bnez rs, l", "BEQ / BNE rs, x0, l"), ("bltz / bgez rs, l", "BLT / BGE rs, x0, l"),
    ("blez / bgtz rs, l", "BGE / BLT x0, rs, l"), ("bgt / ble a, b, l", "BLT / BGE b, a, l"),
    ("bgtu / bleu a, b, l", "BLTU / BGEU b, a, l"),
]

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def encode(line):
    """machine word for one instruction, via the project's own assembler"""
    out = subprocess.run([sys.executable, str(RVASM), "-e", line, "--plain"],
                         capture_output=True, text=True)
    word = out.stdout.strip().split()[0] if out.returncode == 0 and out.stdout.strip() else "????????"
    return word.upper()


def e(s):
    return html.escape(str(s))


def fmt_diagram(name):
    fields = FORMATS[name]
    cells, hi = [], 31
    for label, w in fields:
        lo = hi - w + 1
        rng = f"{hi}" if w == 1 else f"{hi}&nbsp;&nbsp;·&nbsp;&nbsp;{lo}"
        cls = "f-op" if label == "opcode" else ("f-imm" if label.startswith("imm") else
              ("f-fn" if label.startswith("funct") else "f-reg"))
        cells.append(f'<div class="fld {cls}" style="grid-column: span {w}">'
                     f'<span class="bits">{rng}</span><span class="lbl">{e(label)}</span></div>')
        hi = lo - 1
    return (f'<div class="fmt-row"><div class="fmt-tag t-{name}">{name}</div>'
            f'<div class="fmt-grid">{"".join(cells)}</div></div>')


def chip(name, val):
    v = "—" if val == "x" else val
    dim = " dim" if val == "x" else ""
    return f'<span class="chip{dim}"><b>{e(name)}</b>{e(v)}</span>'


def group_card(g):
    c = g["ctrl"]
    chips = "".join(chip(k, v) for k, v in c.items() if v is not None)
    is_u = g["key"] == "U"
    is_b = g["key"] == "B"
    if is_u:
        head = ["Instr", "Assembly", "Operation", "opcode", "alu_a_sel", "alu_op", "Example", "Machine code"]
    else:
        last = "br_cond" if is_b else "alu_op"
        head = ["Instr", "Assembly", "Operation", "funct3", "funct7", last, "Example", "Machine code"]
    rows = []
    for (ins, asm, op, f3, f7, alu, ex) in g["rows"]:
        rows.append(
            "<tr>"
            f'<td class="ins">{e(ins)}</td><td class="mono">{e(asm)}</td><td class="op">{e(op)}</td>'
            f'<td class="mono c">{e(f3)}</td><td class="mono c">{e(f7)}</td>'
            f'<td class="mono">{e(alu)}</td><td class="mono ex">{e(ex)}</td>'
            f'<td class="mono hex">{encode(ex)}</td>'
            "</tr>")
    meta = (f'<span class="meta">opcode <b class="mono">{g["opcode"]}</b> · {g["pkg"]}</span>'
            if g["opcode"] else '<span class="meta">opcodes OP_LUI / OP_AUIPC</span>')
    return f"""
<section class="card g-{g['fmt']}">
  <header>
    <div class="ttl"><span class="fmt-tag t-{g['fmt']}">{g['fmt']}</span><h3>{e(g['title'])}</h3>{meta}</div>
    <div class="chips">{chips}</div>
  </header>
  <table class="ins-tbl">
    <thead><tr>{''.join(f'<th>{h}</th>' for h in head)}</tr></thead>
    <tbody>{''.join(rows)}</tbody>
  </table>
  <footer><span>{e(g['note'])}</span><span class="tb">verified by {e(g['tb'])}</span></footer>
</section>"""


def control_matrix():
    cols = ["alu_op", "alu_src", "alu_a_sel", "wb_sel", "reg_we", "mem_we", "branch", "jump", "jalr"]
    body = []
    labels = {"R": "OP_R", "I": "OP_IMM", "L": "OP_LOAD", "S": "OP_STORE", "B": "OP_BRANCH",
              "JAL": "OP_JAL", "JALR": "OP_JALR"}
    rows = [(labels[g["key"]], g["ctrl"], g["fmt"]) for g in GROUPS if g["key"] != "U"]
    u = next(g for g in GROUPS if g["key"] == "U")
    rows.append(("OP_LUI", dict(u["ctrl"], alu_a_sel="2"), "U"))
    rows.append(("OP_AUIPC", dict(u["ctrl"], alu_a_sel="1"), "U"))
    rows.append(("other", dict(alu_op="ALU_ADD", alu_src="0", alu_a_sel="0", wb_sel="0", reg_we="0",
                               mem_we="0", branch="0", jump="0", jalr="0"), ""))
    for name, ctrl, fmt in rows:
        tds = []
        for col in cols:
            v = ctrl.get(col)
            if v is None:
                v = "{b30,f3}" if name == "OP_R" else "{0,f3}*"
            cls = "on" if v not in ("0", "x", "ALU_ADD") else ""
            tds.append(f'<td class="mono c {cls}">{"—" if v == "x" else e(v)}</td>')
        tag = f'<span class="fmt-tag sm t-{fmt}">{fmt}</span>' if fmt else ""
        body.append(f'<tr><td class="mono">{tag}{e(name)}</td>{"".join(tds)}</tr>')
    return ('<table class="matrix"><thead><tr><th>opcode</th>'
            + "".join(f"<th>{c}</th>" for c in cols) + "</tr></thead><tbody>"
            + "".join(body) + "</tbody></table>")


def simple_table(head, rows, cls=""):
    return (f'<table class="simple {cls}"><thead><tr>' + "".join(f"<th>{h}</th>" for h in head)
            + "</tr></thead><tbody>"
            + "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in rows)
            + "</tbody></table>")


def m(s):
    return f'<span class="mono">{e(s)}</span>'


# ---------------------------------------------------------------------------
# page
# ---------------------------------------------------------------------------

CSS = """
@page { size: A4; margin: 0; }
:root {
  --ink:#1b2230; --ink2:#4a5468; --ink3:#8a93a6; --line:#dfe3ea; --paper:#ffffff; --tint:#f5f7fa;
  --R:#127a6a; --I:#2f62b8; --S:#b26a12; --B:#c2492f; --U:#6a4bb5; --J:#b03a78;
  --Rb:#e3f3f0; --Ib:#e6eefb; --Sb:#fbf0e1; --Bb:#fbe8e3; --Ub:#eeeafa; --Jb:#f8e6ef;
}
* { box-sizing:border-box; margin:0; padding:0; }
html, body { background:var(--paper); }
body { font-family:"Inter","Segoe UI","Helvetica Neue",Arial,sans-serif; color:var(--ink);
       font-size:8.6pt; line-height:1.4; -webkit-print-color-adjust:exact; print-color-adjust:exact; }
.mono { font-family:"JetBrains Mono","DejaVu Sans Mono",Consolas,monospace; font-size:0.93em; }
.page { width:210mm; height:297mm; padding:13mm 12mm 14mm; position:relative; page-break-after:always;
        overflow:hidden; }
.page:last-child { page-break-after:auto; }
.pfoot { position:absolute; left:12mm; right:12mm; bottom:7mm; display:flex; justify-content:space-between;
         font-size:7pt; color:var(--ink3); border-top:0.5pt solid var(--line); padding-top:2mm; }
h1 { font-size:22pt; font-weight:700; letter-spacing:-0.02em; }
h2 { font-size:11.5pt; font-weight:650; margin:0 0 2.5mm; display:flex; align-items:baseline; gap:3mm; }
h2 small { font-size:8pt; font-weight:400; color:var(--ink3); }
h3 { font-size:10.5pt; font-weight:650; }
p.lead { color:var(--ink2); font-size:9.3pt; max-width:160mm; margin-top:2mm; }
.kicker { font-size:7.5pt; letter-spacing:0.14em; text-transform:uppercase; color:var(--ink3); font-weight:600; }
.cover { border-bottom:0.6pt solid var(--line); padding-bottom:5mm; margin-bottom:5mm; }
.stats { display:flex; gap:3mm; margin-top:4.5mm; }
.stat { flex:1; background:var(--tint); border-radius:2mm; padding:2.6mm 3mm; }
.stat b { display:block; font-size:15pt; font-weight:700; letter-spacing:-0.02em; }
.stat span { color:var(--ink2); font-size:7.6pt; }
section.block { margin-bottom:5mm; }

/* formats */
.fmt-row { display:flex; align-items:stretch; gap:2.5mm; margin-bottom:1.6mm; }
.fmt-grid { flex:1; display:grid; grid-template-columns:repeat(32, 1fr); gap:0.6mm; }
.fld { border-radius:1.2mm; padding:1.1mm 1mm 1.2mm; text-align:center; display:flex; flex-direction:column;
       justify-content:center; min-height:9.5mm; }
.fld .bits { font-family:"JetBrains Mono","DejaVu Sans Mono",monospace; font-size:6pt; color:var(--ink3); }
.fld .lbl { font-family:"JetBrains Mono","DejaVu Sans Mono",monospace; font-size:7.3pt; font-weight:600; white-space:nowrap; }
.f-op { background:#e9ecf1; } .f-reg { background:#dcefe9; } .f-fn { background:#e5e9f7; } .f-imm { background:#fbecd6; }
.fmt-tag { display:inline-flex; align-items:center; justify-content:center; min-width:7mm; height:7mm; border-radius:1.4mm;
           color:#fff; font-weight:700; font-size:9pt; flex:none; padding:0 1.4mm; }
.fmt-row .fmt-tag { height:auto; min-width:9mm; font-size:11pt; }
.fmt-tag.sm { min-width:5mm; height:4.4mm; font-size:6.6pt; margin-right:1.6mm; border-radius:1mm; vertical-align:middle; }
.t-R{background:var(--R)} .t-I{background:var(--I)} .t-S{background:var(--S)} .t-B{background:var(--B)} .t-U{background:var(--U)} .t-J{background:var(--J)}
.legend { display:flex; gap:4mm; font-size:7.3pt; color:var(--ink2); margin-top:1.5mm; }
.legend i { display:inline-block; width:3mm; height:3mm; border-radius:0.7mm; margin-right:1.2mm; vertical-align:-0.4mm; }

/* tables */
table { border-collapse:collapse; width:100%; }
th { text-align:left; font-weight:600; font-size:7pt; color:var(--ink3); text-transform:uppercase;
     letter-spacing:0.05em; padding:1.3mm 1.6mm; border-bottom:0.6pt solid var(--line); }
td { padding:1.25mm 1.6mm; border-bottom:0.4pt solid #eef0f4; vertical-align:top; }
tr:last-child td { border-bottom:none; }
td.c, th.c { text-align:center; }
.simple td:first-child { font-weight:600; }
.two { display:grid; grid-template-columns:1fr 1fr; gap:6mm; }
.three { display:grid; grid-template-columns:1.1fr 1fr 1fr; gap:5mm; }

/* instruction cards */
.card { border:0.6pt solid var(--line); border-radius:2.4mm; margin-bottom:4mm; overflow:hidden; break-inside:avoid; }
.card header { padding:2.4mm 3mm 2mm; border-bottom:0.6pt solid var(--line); }
.card .ttl { display:flex; align-items:center; gap:2.4mm; }
.card .meta { margin-left:auto; color:var(--ink2); font-size:7.6pt; }
.chips { display:flex; flex-wrap:wrap; gap:1.2mm; margin-top:1.8mm; }
.chip { font-family:"JetBrains Mono","DejaVu Sans Mono",monospace; font-size:6.8pt; background:var(--tint);
        border-radius:1mm; padding:0.5mm 1.5mm; color:var(--ink); }
.chip b { font-weight:400; color:var(--ink3); margin-right:1mm; }
.chip.dim { color:var(--ink3); }
.g-R header{background:var(--Rb)} .g-I header{background:var(--Ib)} .g-S header{background:var(--Sb)}
.g-B header{background:var(--Bb)} .g-U header{background:var(--Ub)} .g-J header{background:var(--Jb)}
.g-R .chip,.g-I .chip,.g-S .chip,.g-B .chip,.g-U .chip,.g-J .chip { background:rgba(255,255,255,0.75); }
.ins-tbl td { font-size:8pt; }
.ins-tbl td.mono { white-space:nowrap; }
.ins-tbl td.ins { font-weight:700; width:12mm; }
.ins-tbl td.op { color:var(--ink); }
.ins-tbl td.ex { color:var(--ink2); }
.ins-tbl td.hex { font-weight:600; letter-spacing:0.04em; }
.card footer { display:flex; justify-content:space-between; gap:4mm; padding:1.8mm 3mm 2mm; background:var(--tint);
               color:var(--ink2); font-size:7.2pt; border-top:0.4pt solid var(--line); }
.card footer .tb { white-space:nowrap; color:var(--ink3); }

/* matrix */
.matrix td, .matrix th { padding:1.2mm 1.3mm; font-size:7.6pt; }
.matrix td.on { font-weight:700; color:var(--ink); background:#f1f5fb; }
.matrix td { color:var(--ink3); }
.matrix td:first-child { color:var(--ink); white-space:nowrap; }
.sig td:first-child { font-family:"JetBrains Mono","DejaVu Sans Mono",monospace; font-weight:600; }
.note { background:var(--tint); border-radius:2mm; padding:2.4mm 3mm; color:var(--ink2); font-size:7.8pt; }
.note b { color:var(--ink); }
.lanes { display:grid; grid-template-columns:repeat(4,1fr); gap:0.8mm; margin:1.5mm 0; }
.lane { text-align:center; border-radius:1mm; padding:1mm 0; font-family:"JetBrains Mono","DejaVu Sans Mono",monospace;
        font-size:7pt; background:#eef1f5; }
.lane.hit { background:var(--S); color:#fff; font-weight:700; }
.lanecap { font-size:7pt; color:var(--ink3); display:flex; justify-content:space-between; }
"""


def build_html():
    today = datetime.date.today().strftime("%d %b %Y")
    n_ins = sum(len(g["rows"]) for g in GROUPS)

    def foot(n, total):
        return (f'<div class="pfoot"><span>arielhuna/riscv-cpu · RV32I single-cycle core · reference</span>'
                f'<span>{today} · page {n} / {total}</span></div>')

    total = 5
    fmts = "".join(fmt_diagram(k) for k in FORMATS)
    abi_rows = [(m(r), m(n), d) for r, n, d in ABI]
    half = (len(abi_rows) + 1) // 2

    page1 = f"""
<div class="page">
  <div class="cover">
    <div class="kicker">Instruction reference</div>
    <h1>RV32I on arielhuna/riscv-cpu</h1>
    <p class="lead">Every instruction this single-cycle SystemVerilog core executes: encoding, behaviour,
    the control signals <span class="mono">rtl/control.sv</span> drives for it, and a machine-code example
    produced by <span class="mono">rvasm.py</span>.</p>
    <div class="stats">
      <div class="stat"><b>{n_ins}</b><span>instructions implemented</span></div>
      <div class="stat"><b>9</b><span>opcodes decoded</span></div>
      <div class="stat"><b>6</b><span>encoding formats</span></div>
      <div class="stat"><b>32 × 32</b><span>register file, x0 = 0</span></div>
      <div class="stat"><b>1 CPI</b><span>single cycle, Harvard</span></div>
    </div>
  </div>

  <section class="block">
    <h2>Encoding formats <small>32-bit, little-endian, bit 31 on the left</small></h2>
    {fmts}
    <div class="legend"><span><i style="background:#e9ecf1"></i>opcode</span><span><i style="background:#dcefe9"></i>register</span>
      <span><i style="background:#e5e9f7"></i>function</span><span><i style="background:#fbecd6"></i>immediate</span>
      <span style="margin-left:auto">rs1, rs2, rd and the sign bit (instr[31]) sit in the same place in every format.</span></div>
  </section>

  <section class="block">
    <h2>Immediate generator <small>rtl/immgen.sv · i = instr</small></h2>
    {simple_table(["Fmt", "Used by", "imm[31:0]", "Range"],
                  [(f'<span class="fmt-tag sm t-{f}">{f}</span>', e(u), m(x), e(r)) for f, u, x, r in IMMGEN])}
  </section>

  <section class="block">
    <h2>Registers <small>ABI names accepted by rvasm.py</small></h2>
    <div class="two">
      {simple_table(["Reg", "ABI", "Role"], abi_rows[:half])}
      {simple_table(["Reg", "ABI", "Role"], abi_rows[half:])}
    </div>
  </section>
  {foot(1, total)}
</div>"""

    g = {x["key"]: x for x in GROUPS}
    page2 = f"""
<div class="page">
  <h2>Arithmetic and logic <small>ALU instructions, result written to rd</small></h2>
  {group_card(g['R'])}
  {group_card(g['I'])}
  {foot(2, total)}
</div>"""

    page3 = f"""
<div class="page">
  <h2>Memory, control flow and constants</h2>
  {group_card(g['L'])}
  {group_card(g['S'])}
  {group_card(g['B'])}
  {foot(3, total)}
</div>"""

    page4 = f"""
<div class="page">
  <h2>Jumps and upper immediates</h2>
  {group_card(g['JAL'])}
  {group_card(g['JALR'])}
  {group_card(g['U'])}
  <section class="block" style="margin-top:5mm">
    <div class="two">
      <div><h2>Pseudo-instructions <small>expanded by rvasm.py</small></h2>
        {simple_table(["Pseudo", "Becomes"], [(m(p), m(r)) for p, r in PSEUDOS[:9]])}</div>
      <div><h2 style="visibility:hidden">.</h2>
        {simple_table(["Pseudo", "Becomes"], [(m(p), m(r)) for p, r in PSEUDOS[9:]])}</div>
    </div>
  </section>
  <div class="note"><b>Not implemented:</b> FENCE, ECALL, EBREAK (decoded as NOP), CSR instructions, misaligned
  accesses and traps. Memories: imem and dmem are 256 words each, word index = addr[9:2].</div>
  {foot(4, total)}
</div>"""

    sig_rows = [(e(n), e(w), e(d)) for n, w, d in SIGNALS]
    alu_rows = [(m(n), m(c), m(o)) for n, c, o in ALU_OPS]
    br_rows = [(m("000"), "BEQ", m("alu_zero")), (m("001"), "BNE", m("~alu_zero")),
               (m("100"), "BLT", m("lt")), (m("101"), "BGE", m("~lt")),
               (m("110"), "BLTU", m("ltu")), (m("111"), "BGEU", m("~ltu")),
               (m("010/011"), "—", m("1'b0"))]
    npc_rows = [(m("1 0"), "JALR", m("{alu_out[31:1], 1'b0}")),
                (m("0 1"), "JAL, taken branch", m("pc_target = pc + imm")),
                (m("else"), "everything else", m("pc_plus4"))]

    def lanes(hit, cap):
        cells = "".join(f'<div class="lane{" hit" if i in hit else ""}">{["[31:24]","[23:16]","[15:8]","[7:0]"][3-i]}</div>'
                        for i in (3, 2, 1, 0))
        return f'<div class="lanecap"><span>{cap}</span></div><div class="lanes">{cells}</div>'

    page5 = f"""
<div class="page">
  <section class="block">
    <h2>Control unit <small>rtl/control.sv · values set per opcode · bold = active</small></h2>
    {control_matrix()}
    <p style="font-size:7.2pt;color:var(--ink3);margin-top:1.2mm">* OP_IMM: {{1'b0, funct3}}, except funct3 = 101 → {{instr[30], funct3}}.
      “—” = don't care (output unused). “other” = safe NOP defaults at the top of always_comb.</p>
  </section>

  <section class="block">
    <div class="two">
      <div><h2>Signals</h2>{simple_table(["Signal", "Bits", "Meaning"], sig_rows, "sig")}</div>
      <div><h2>ALU operations <small>alu_pkg::alu_op_t</small></h2>{simple_table(["Name", "Code", "result"], alu_rows)}
        <p style="font-size:7.2pt;color:var(--ink3);margin-top:1.2mm">zero = (result == 0). <span class="mono">&lt;ₛ</span> signed,
        <span class="mono">&lt;ᵤ</span> unsigned.</p></div>
    </div>
  </section>

  <section class="block">
    <div class="three">
      <div><h2>Branch condition <small>br_cond</small></h2>{simple_table(["funct3", "Instr", "br_cond"], br_rows)}</div>
      <div><h2>Next PC <small>{{jalr, jump|take}}</small></h2>{simple_table(["Sel", "When", "pc_next"], npc_rows)}</div>
      <div><h2>Memory lanes <small>addr[1:0]</small></h2>
        {lanes({0}, "SB @ addr[1:0] = 00 → be = 0001")}
        {lanes({3}, "SB @ 11 → be = 1000")}
        {lanes({0, 1}, "SH @ addr[1] = 0 → be = 0011")}
        {lanes({2, 3}, "SH @ addr[1] = 1 → be = 1100")}
        <div class="note" style="margin-top:2mm"><b>Rule:</b> register side = low bits, memory side = lane by
        <span class="mono">addr[1:0]</span>.</div></div>
    </div>
  </section>

  {foot(5, total)}
</div>"""

    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>RV32I reference · arielhuna/riscv-cpu</title><style>{CSS}</style></head>
<body>{page1}{page2}{page3}{page4}{page5}</body></html>"""


def find_browser():
    names = ["google-chrome", "chromium", "chromium-browser", "chrome", "msedge"]
    for n in names:
        p = shutil.which(n)
        if p:
            return p
    for p in [r"C:\Program Files\Google\Chrome\Application\chrome.exe",
              r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
              r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
              r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"]:
        if Path(p).exists():
            return p
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--html", action="store_true", help="write the .html only")
    args = ap.parse_args()

    html_path = HERE / "rv32i_reference.html"
    pdf_path = HERE / "rv32i_reference.pdf"
    html_path.write_text(build_html(), encoding="utf-8")
    print(f"wrote {html_path.relative_to(ROOT)}")
    if args.html:
        return

    browser = find_browser()
    if not browser:
        sys.exit("no Chrome/Edge found: open the .html and print it to PDF (margins: none)")
    subprocess.run([browser, "--headless", "--disable-gpu", "--no-pdf-header-footer",
                    f"--print-to-pdf={pdf_path}", html_path.as_uri()],
                   check=True, capture_output=True)
    print(f"wrote {pdf_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
