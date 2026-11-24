#!/usr/bin/env python3
"""
make_pipe_ref.py - build docs/pipeline_reference.pdf

Companion to rv32i_reference.pdf for the 5-stage pipeline (rtl/cpu_pipe.sv):
what each stage does, what each pipeline register (card) carries, the order
instructions move in, the hazards and how lessons 27-29 remove them.

    python docs/make_pipe_ref.py            # writes .html and .pdf
    python docs/make_pipe_ref.py --html     # .html only (open it, Ctrl+P)

Same look and the same Chrome/Edge headless print as make_isa_ref.py.
Edit the tables below when a card gets a new field.
"""

import argparse
import datetime
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from make_isa_ref import CSS as BASE_CSS, e, m, simple_table, find_browser  # noqa: E402

ROOT = HERE.parent

# ---------------------------------------------------------------------------
# data
# ---------------------------------------------------------------------------

STAGES = ["IF", "ID", "EX", "MEM", "WB"]

# name, title, reads from, hardware, job, writes into
STAGE_INFO = [
    ("IF", "Instruction fetch", "pc_cur",
     ["pc", "imem", "pc + 4 adder"],
     "Read the instruction at pc_cur. Pick pc_next (pc + 4, or the target EX asks for).",
     "IF/ID"),
    ("ID", "Decode, register read", "if_id.*",
     ["control", "immgen", "regfile (read ports)"],
     "Split the instruction into fields, make the control signals and imm, read rs1 and rs2.",
     "ID/EX"),
    ("EX", "Execute", "id_ex.*",
     ["alu_a / alu_b MUX", "alu", "pc_target adder", "br_cond, pc_next"],
     "Compute: arithmetic, load/store address, branch compare. Decide if PC jumps.",
     "EX/MEM"),
    ("MEM", "Memory", "ex_mem.*",
     ["dmem", "store lanes (be)", "load shift + extend"],
     "Loads read dmem, stores write it. Everyone else just passes through.",
     "MEM/WB"),
    ("WB", "Write back", "mem_wb.*",
     ["wb_sel MUX", "regfile (write port)"],
     "Choose alu_out / load data / pc + 4 and write it to rd.",
     "regfile"),
]

# card fields: (name, bits, born in, used in, why it travels)
IF_ID = [
    ("pc", 32, "IF", "EX", "pc_target, AUIPC and pc + 4 need the address of THIS instruction"),
    ("instr", 32, "IF", "ID", "decoded in ID, then dropped: later stages get fields instead"),
]
ID_EX = [
    ("pc", 32, "IF", "EX", "copied from if_id.pc"),
    ("rs1_data", 32, "ID", "EX", "ALU input a, branch compare, JALR base"),
    ("rs2_data", 32, "ID", "MEM", "ALU input b, branch compare, store data"),
    ("imm", 32, "ID", "EX", "already sign-extended by immgen"),
    ("rd", 5, "ID", "WB", "the write happens 3 stages later"),
    ("rs1, rs2", 10, "ID", "EX", "compared with rd of older cards (forwarding, lesson 27)"),
    ("funct3", 3, "ID", "MEM", "br_cond in EX, load/store size in MEM"),
    ("alu_op", 4, "ID", "EX", "alu_pkg::alu_op_t"),
    ("alu_src, alu_a_sel", 3, "ID", "EX", "ALU input MUXes"),
    ("branch, jump, jalr", 3, "ID", "EX", "pc_next is chosen in EX"),
    ("mem_we", 1, "ID", "MEM", "only MEM writes memory"),
    ("wb_sel, reg_we", 3, "ID", "WB", "only WB writes the register file"),
]
EX_MEM = [
    ("pc_plus4", 32, "EX", "WB", "id_ex.pc + 4: the link value of JAL / JALR"),
    ("alu_out", 32, "EX", "WB", "result, or the load/store address"),
    ("rs2_data", 32, "ID", "MEM", "store data"),
    ("rd", 5, "ID", "WB", ""),
    ("funct3", 3, "ID", "MEM", "SB/SH/SW, LB/LH/LW/LBU/LHU"),
    ("mem_we", 1, "ID", "MEM", ""),
    ("wb_sel, reg_we", 3, "ID", "WB", ""),
]
MEM_WB = [
    ("pc_plus4", 32, "EX", "WB", "wb_sel = 2"),
    ("alu_out", 32, "EX", "WB", "wb_sel = 0"),
    ("ld_data", 32, "MEM", "WB", "wb_sel = 1, already shifted and extended"),
    ("rd", 5, "ID", "WB", "→ wb_rd"),
    ("wb_sel, reg_we", 3, "ID", "WB", "reg_we → wb_we"),
]

TEST_PROG = [
    ("0x00", "addi t0, x0, 5"),
    ("0x04", "addi t1, x0, -3"),
    ("0x08", "lui t2, 0x12345"),
    ("0x0C", "auipc t3, 1"),
    ("0x10", "done: jal x0, done"),
]

CSS = BASE_CSS + """
.s-IF{background:#e6eefb;color:#1f4a91} .s-ID{background:#e3f3f0;color:#0e5e52}
.s-EX{background:#fbf0e1;color:#8a510c} .s-MEM{background:#eeeafa;color:#4f368f}
.s-WB{background:#f8e6ef;color:#8a2c5d}
.b-IF{background:#2f62b8} .b-ID{background:#127a6a} .b-EX{background:#b26a12} .b-MEM{background:#6a4bb5} .b-WB{background:#b03a78}

/* datapath strip */
.strip { display:flex; align-items:stretch; gap:0; margin:1mm 0 2mm; }
.stg { flex:1; border-radius:2mm; overflow:hidden; border:0.6pt solid var(--line); display:flex; flex-direction:column; }
.stg .hd { color:#fff; padding:1.6mm 2mm; }
.stg .hd b { font-size:11pt; display:block; letter-spacing:-0.01em; }
.stg .hd span { font-size:7pt; opacity:0.9; }
.stg .bd { padding:1.8mm 2mm; font-size:7.4pt; color:var(--ink2); flex:1; }
.stg .bd ul { list-style:none; margin:0.8mm 0 1.4mm; }
.stg .bd li { font-family:"JetBrains Mono","DejaVu Sans Mono",monospace; font-size:6.8pt; color:var(--ink);
             background:var(--tint); border-radius:0.8mm; padding:0.4mm 1.2mm; margin-bottom:0.7mm; }
.stg .rd { font-size:6.6pt; color:var(--ink3); }
.stg .rd .mono { color:var(--ink); }
.reg { width:6.5mm; margin:0 1.4mm; border-radius:1mm; background:#cfd6e2; display:flex; align-items:center;
       justify-content:center; position:relative; }
.reg span { writing-mode:vertical-rl; transform:rotate(180deg); font-family:"JetBrains Mono","DejaVu Sans Mono",monospace;
            font-size:7pt; font-weight:700; color:#33405a; }
.reg.next { background:repeating-linear-gradient(45deg,#e8ecf2,#e8ecf2 1.2mm,#f6f7fa 1.2mm,#f6f7fa 2.4mm); }

/* pipeline (instruction x cycle) grid */
.pg { border-collapse:separate; border-spacing:0.7mm; width:auto; }
.pg th { text-transform:none; letter-spacing:0; font-size:7pt; padding:0.6mm 1mm; border:none; text-align:center; }
.pg td { border:none; padding:0; text-align:center; font-family:"JetBrains Mono","DejaVu Sans Mono",monospace;
         font-size:7pt; font-weight:700; width:10mm; height:5.6mm; vertical-align:middle; border-radius:1mm; }
.pg td.lbl { text-align:left; font-weight:400; color:var(--ink); width:auto; padding-right:2mm; white-space:nowrap; }
.pg td.lbl .a { color:var(--ink3); margin-right:1.5mm; }
.pg td.e { background:transparent; }
.pg td.col { outline:0.9pt solid #1b2230; }
.pg td.bub { background:#f0f1f4; color:var(--ink3); font-weight:400; }
.pg td.fl { background:#f0f1f4; color:#b0b5c0; text-decoration:line-through; font-weight:400; }
.pg td.hot { box-shadow:inset 0 0 0 0.9pt #c2492f; }

/* lifespan bars */
.life td { padding:0.9mm 1.4mm; }
.life td.bar { padding:0.9mm 0; width:13mm; }
.life td.bar i { display:block; height:3.2mm; }
.life td.bar i.on { background:#c9d3e6; }
.life td.bar i.born { background:#2f62b8; border-radius:1mm 0 0 1mm; }
.life td.bar i.use { background:#c2492f; border-radius:0 1mm 1mm 0; }
.life td.bar i.both { background:#6a4bb5; border-radius:1mm; }
.life th.c { text-align:center; }

.cardbox { border:0.6pt solid var(--line); border-radius:2.4mm; overflow:hidden; margin-bottom:3mm; break-inside:avoid; }
.cardbox header { padding:1.8mm 3mm; border-bottom:0.6pt solid var(--line); display:flex; align-items:center; gap:2.4mm; }
.cardbox header h3 { font-size:10pt; }
.cardbox header .meta { margin-left:auto; font-size:7.4pt; color:var(--ink2); }
.cardbox table td { font-size:7.6pt; padding:0.9mm 2mm; }
.cardbox footer { padding:1.5mm 3mm; background:var(--tint); color:var(--ink2); font-size:7.2pt; border-top:0.4pt solid var(--line); }
.tag { display:inline-block; font-family:"JetBrains Mono","DejaVu Sans Mono",monospace; font-size:6.6pt; font-weight:700;
       border-radius:0.8mm; padding:0.2mm 1.2mm; }
.plan { font-size:6.8pt; color:#8a510c; background:#fbf0e1; border-radius:0.8mm; padding:0.2mm 1.4mm; font-weight:600; }
.rule { display:flex; gap:2.5mm; align-items:flex-start; margin-bottom:1.6mm; }
.rule .n { flex:none; width:5mm; height:5mm; border-radius:50%; background:var(--ink); color:#fff; font-size:7.4pt;
           font-weight:700; display:flex; align-items:center; justify-content:center; }
.rule div { font-size:8pt; color:var(--ink2); }
.rule div b { color:var(--ink); }
.hz { border:0.6pt solid var(--line); border-radius:2.4mm; padding:2.4mm 3mm; margin-bottom:3mm; break-inside:avoid; }
.hz h3 { display:flex; align-items:center; gap:2mm; margin-bottom:1.2mm; }
.hz h3 .cost { margin-left:auto; font-size:7.6pt; font-weight:600; color:var(--ink2); }
.hz p { font-size:7.9pt; color:var(--ink2); margin-bottom:1.4mm; }
.hz .cols { display:grid; grid-template-columns:1.15fr 1fr; gap:4mm; align-items:start; }
pre.code { font-family:"JetBrains Mono","DejaVu Sans Mono",monospace; font-size:6.9pt; background:#f6f7fa; border-radius:1.4mm;
           padding:1.8mm 2.2mm; color:#1b2230; white-space:pre; line-height:1.38; }
pre.code .c { color:#8a93a6; }
.big { font-size:13pt; font-weight:700; letter-spacing:-0.01em; }
.cmp td { font-size:7.8pt; }
.ok { color:#127a6a; font-weight:700; } .bad { color:#c2492f; font-weight:700; }
"""


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def stag(s):
    return f'<span class="tag s-{s}">{s}</span>'


def strip():
    out = []
    for i, (s, title, reads, hw, job, writes) in enumerate(STAGE_INFO):
        items = "".join(f"<li>{e(h)}</li>" for h in hw)
        out.append(f"""
<div class="stg"><div class="hd b-{s}"><b>{s}</b><span>{e(title)}</span></div>
  <div class="bd">{e(job)}<ul>{items}</ul>
  <div class="rd">reads <span class="mono">{e(reads)}</span></div></div></div>""")
        if i < 4:
            cls = "reg"
            out.append(f'<div class="{cls}"><span>{STAGES[i]}/{STAGES[i + 1]}</span></div>')
    return f'<div class="strip">{"".join(out)}</div>'


def card(name, fields, stage_from, note, planned=False):
    total = sum(b for _, b, *_ in fields)
    rows = []
    for f, b, born, used, why in fields:
        rows.append(f"<tr><td class='mono' style='font-weight:600;white-space:nowrap'>{e(f)}</td>"
                    f"<td class='mono c'>{b}</td><td class='c'>{stag(born)}</td><td class='c'>{stag(used)}</td>"
                    f"<td style='color:var(--ink2)'>{e(why)}</td></tr>")
    plan = '<span class="plan">planned · lesson 26b</span>' if planned else ""
    t = name.replace("/", "_").lower()
    return f"""
<section class="cardbox">
  <header><span class="tag s-{stage_from}" style="font-size:8pt">{name}</span><h3 class="mono">{t}_t</h3>{plan}
    <span class="meta">{total} bits · end of {stage_from}</span></header>
  <table><thead><tr><th>field</th><th class="c">bits</th><th class="c">born</th><th class="c">last used</th><th>why it travels</th></tr></thead>
  <tbody>{''.join(rows)}</tbody></table>
  <footer>{note}</footer>
</section>"""


def pipe_grid(rows, ncycles, mark_col=None, first_cycle=1):
    """rows: list of (label_addr, label_text, {cycle: (text, cls)})"""
    head = "<tr><th></th>" + "".join(f"<th>c{c}</th>" for c in range(first_cycle, first_cycle + ncycles)) + "</tr>"
    body = []
    for addr, text, cells in rows:
        tds = [f'<td class="lbl"><span class="a">{e(addr)}</span>{e(text)}</td>']
        for c in range(first_cycle, first_cycle + ncycles):
            if c in cells:
                txt, cls = cells[c]
                col = " col" if c == mark_col else ""
                tds.append(f'<td class="{cls}{col}">{e(txt)}</td>')
            else:
                tds.append('<td class="e"></td>')
        body.append("<tr>" + "".join(tds) + "</tr>")
    return f'<table class="pg">{head}{"".join(body)}</table>'


def flow(start, stages=STAGES, extra=None):
    d = {start + i: (s, f"s-{s}") for i, s in enumerate(stages)}
    if extra:
        d.update(extra)
    return d


def life_table():
    sigs = [
        ("pc", "IF", "EX", "if_id → id_ex"),
        ("instr", "IF", "ID", "if_id only"),
        ("imm, rs1_data", "ID", "EX", "id_ex"),
        ("branch, jump, jalr", "ID", "EX", "id_ex"),
        ("rs2_data (store)", "ID", "MEM", "id_ex → ex_mem"),
        ("mem_we, funct3", "ID", "MEM", "id_ex → ex_mem"),
        ("alu_out", "EX", "WB", "ex_mem → mem_wb"),
        ("pc + 4 (link)", "EX", "WB", "ex_mem → mem_wb"),
        ("ld_data", "MEM", "WB", "mem_wb"),
        ("rd, reg_we, wb_sel", "ID", "WB", "id_ex → ex_mem → mem_wb"),
    ]
    rows = []
    for name, born, used, path in sigs:
        b, u = STAGES.index(born), STAGES.index(used)
        cells = []
        for i in range(5):
            if i == b == u:
                cls = "both"
            elif i == b:
                cls = "born"
            elif i == u:
                cls = "use"
            elif b < i < u:
                cls = "on"
            else:
                cls = ""
            cells.append(f'<td class="bar"><i class="{cls}"></i></td>')
        rows.append(f"<tr><td class='mono' style='font-weight:600;white-space:nowrap'>{e(name)}</td>{''.join(cells)}"
                    f"<td class='mono' style='color:var(--ink2);font-size:7pt'>{e(path)}</td></tr>")
    head = ("<tr><th>signal</th>" + "".join(f'<th class="c">{s}</th>' for s in STAGES) + "<th>rides in</th></tr>")
    return f'<table class="life">{head}{"".join(rows)}</table>'


# ---------------------------------------------------------------------------
# pages
# ---------------------------------------------------------------------------

def build_html():
    today = datetime.date.today().strftime("%d %b %Y")
    total = 5

    def foot(n):
        return (f'<div class="pfoot"><span>arielhuna/riscv-cpu · RV32I 5-stage pipeline · reference</span>'
                f'<span>{today} · page {n} / {total}</span></div>')

    # ---------------- page 1: overview + stages ----------------
    stage_rows = [
        (stag("IF"), "every", m("pc_cur"), "imem, pc", m("if_id"), "nothing (pc only)"),
        (stag("ID"), "every", m("if_id.*"), "control, immgen, regfile read", m("id_ex"), "nothing"),
        (stag("EX"), "every", m("id_ex.*"), "alu, pc_target, br_cond", m("ex_mem"), "pc_next (jump / taken branch)"),
        (stag("MEM"), "LW…, SW…", m("ex_mem.*"), "dmem", m("mem_wb"), "dmem (stores)"),
        (stag("WB"), "reg_we = 1", m("mem_wb.*"), "wb_sel MUX", "—", "regfile (rd)"),
    ]
    page1 = f"""
<div class="page">
  <div class="cover">
    <div class="kicker">Pipeline reference</div>
    <h1>5-stage pipeline on arielhuna/riscv-cpu</h1>
    <p class="lead">How <span class="mono">rtl/cpu_pipe.sv</span> splits the single-cycle core into five stages:
    what each stage does, what every pipeline register (“card”) carries and why, the order instructions move in,
    and the hazards that lessons 27–29 remove. Companion to <span class="mono">rv32i_reference.pdf</span>.</p>
    <div class="stats">
      <div class="stat"><b>5</b><span>stages: IF ID EX MEM WB</span></div>
      <div class="stat"><b>4</b><span>pipeline registers (cards)</span></div>
      <div class="stat"><b>8 ns</b><span>clock = slowest stage (paper)</span></div>
      <div class="stat"><b>×4</b><span>max speed-up, if stages were equal</span></div>
      <div class="stat"><b>CPI ≈ 1</b><span>plus stalls and flushes</span></div>
    </div>
  </div>

  <section class="block">
    <h2>The five stages <small>left to right = order · grey bars = cards</small></h2>
    {strip()}
  </section>

  <section class="block">
    <h2>Who reads what <small>each stage only looks at the card on its left</small></h2>
    {simple_table(["Stage", "Busy for", "Inputs from", "Hardware", "Fills card", "Changes state"], stage_rows)}
  </section>

  <section class="block">
    <h2>Why it is faster <small>numbers from lesson 25 (paper estimate)</small></h2>
    <div class="two">
      <div>
        {simple_table(["", "Single-cycle", "Pipeline"], [
            ("Clock period", "32 ns (all stages in a row)", "8 ns (slowest stage)"),
            ("Time for N instr.", m("N × 32"), m("(N + 4) × 8")),
            ("4 instructions", "128 ns", "64 ns · ×2"),
            ("test_sort (~101)", "3232 ns", "840 ns · ×3.8"),
            ("One instruction (latency)", "32 ns", "40 ns · slower!"),
        ], "cmp")}
      </div>
      <div class="note" style="font-size:7.9pt">
        <b>Throughput goes up, latency does not.</b> Each instruction still passes all five stages
        (5 × 8 = 40 ns, a bit more than 32 because every stage waits for the slowest one).
        The gain comes from overlap: once the pipe is full, one instruction finishes every cycle.<br><br>
        <b>Why not ×5:</b> stages are not equal (ceiling ×4 = 32 / 8), the first instruction needs
        4 extra cycles to fill the pipe, and hazards add stalls and flushes.<br><br>
        <b>Measured on the Basys 3</b> (30b): single-cycle 94.4 MHz, pipeline 90.5 MHz. LUTRAM memories read in ~1 ns,
        so the stages are tiny and the hazard logic in EX costs as much as the whole single-cycle path (page 5).
      </div>
    </div>
  </section>
  {foot(1)}
</div>"""

    # ---------------- page 2: cards ----------------
    page2 = f"""
<div class="page">
  <h2>Pipeline registers <small>a card is everything the instruction will still need · one always_ff, reset = NOP</small></h2>
  <div class="two">
    <div>
      {card("IF/ID", IF_ID, "IF", "Reset: <span class='mono'>pc = 0, instr = 32'h00000013</span> (ADDI x0, x0, 0). "
            "In hardware a flip-flop wakes up random, not x: a random SW would write memory.")}
      {card("ID/EX", ID_EX, "ID", "Reset: <span class='mono'>id_ex &lt;= '0</span>. All control = 0 means NOP: "
            "no register write, no memory write, no jump. alu_op = 0 = ALU_ADD, harmless.")}
    </div>
    <div>
      {card("EX/MEM", EX_MEM, "EX", "pc + 4 is computed from <span class='mono'>id_ex.pc</span>, not from "
            "<span class='mono'>pc_plus4</span> (that one belongs to IF).")}
      {card("MEM/WB", MEM_WB, "MEM", "WB drives the regfile write port: "
            "<span class='mono'>wb_we = mem_wb.reg_we, wb_rd = mem_wb.rd</span>. "
            "One driver per wire: the TEMP 0 assigns in ID were deleted, not kept.")}
      <div class="note"><b>Why a struct packed:</b> all fields glued into one vector, first field = top bits
      (<span class="mono">if_id_t = {{pc, instr}}</span>, 64 bits). One register, one reset line,
      but every field still has a name: <span class="mono">id_ex.rd</span>.</div>
    </div>
  </div>


  {foot(2)}
</div>"""

    # ---------------- page 3: order / timing ----------------
    rows = []
    for k, (a, t) in enumerate(TEST_PROG):
        rows.append((a, t, flow(k)))
    grid1 = pipe_grid(rows, 9, mark_col=4, first_cycle=0)

    snap = simple_table(["Stage", "Instruction in cycle 4", "Comes from"], [
        (stag("IF"), m("0x10  jal (done)"), m("pc_cur = 0x10")),
        (stag("ID"), m("0x0C  auipc t3, 1"), m("if_id")),
        (stag("EX"), m("0x08  lui t2"), m("id_ex")),
        (stag("MEM"), m("0x04  addi t1"), m("ex_mem")),
        (stag("WB"), m("0x00  addi t0"), m("mem_wb")),
    ])

    page3 = f"""
<div class="page">
  <section class="block" >
    <h2>Life of a signal <small>blue = born · red = last used · grey = riding in cards</small></h2>
    {life_table()}
    <p style="font-size:7.3pt;color:var(--ink3);margin-top:1.2mm">A signal must be copied into every card between
    the stage that makes it and the stage that uses it. Forgetting one hop is the classic pipeline bug: the later stage
    silently reads the value of a different instruction.</p>
  </section>
  <h2>Order: instruction × cycle <small>test_pipe_a.s · c0 = first cycle after reset, same numbering as tb_cpu_pipe_a</small></h2>
  <div style="display:flex;gap:6mm;align-items:flex-start">
    <div>{grid1}</div>
    <div class="note" style="flex:1;font-size:7.8pt">
      <b>Read a row</b> = the life of one instruction: it enters IF in its own cycle and moves one stage right per clock.<br><br>
      <b>Read a column</b> = one moment: five different instructions, one per stage, oldest at the bottom-right.<br><br>
      <b>Diagonal</b> = the pipe filling. From c4 on, one instruction finishes every cycle.
    </div>
  </div>

  <section class="block" style="margin-top:3mm">
    <div class="two">
      <div><h2>Snapshot of cycle 4 <small>the boxed column</small></h2>{snap}</div>
      <div><h2>Same cycle, the PC <small>why cards carry pc</small></h2>
        {simple_table(["Cycle", "auipc t3 (0x0C) is in", "pc_cur"], [
            ("c3", stag("IF"), m("0x0C")), ("c4", stag("ID"), m("0x10")),
            ("c5", stag("EX") + " ← uses pc", m("0x14")),
        ])}
        <p style="font-size:7.5pt;color:var(--ink2);margin-top:1.4mm">In EX, <span class="mono">pc_cur</span> is already
        8 ahead. AUIPC with pc_cur would give 0x1014 instead of <b>0x100C</b>. Use <span class="mono">id_ex.pc</span>.</p>
      </div>
    </div>
  </section>

  <section class="block">
    <h2>The rules of the pipe</h2>
    <div class="two">
      <div>
        <div class="rule"><span class="n">1</span><div><b>A stage reads only the card on its left.</b> IF → pc_cur,
          ID → <span class="mono">if_id.*</span>, EX → <span class="mono">id_ex.*</span>, MEM → <span class="mono">ex_mem.*</span>,
          WB → <span class="mono">mem_wb.*</span>.</div></div>
        <div class="rule"><span class="n">2</span><div><b>All cards move on the same edge.</b> Each is one
          <span class="mono">always_ff</span> with <span class="mono">&lt;=</span>, so every stage hands over at the same instant.</div></div>
        <div class="rule"><span class="n">3</span><div><b>What a later stage needs, the instruction carries.</b>
          <span class="mono">pc</span>, <span class="mono">rd</span>, <span class="mono">reg_we</span>: never re-read them from an earlier stage.</div></div>
      </div>
      <div>
        <div class="rule"><span class="n">4</span><div><b>Two exceptions, both correct.</b> <span class="mono">pc_next</span>'s default is
          <span class="mono">pc_plus4</span> of IF (keep fetching), and the regfile write port comes from WB while the read ports serve ID.</div></div>
        <div class="rule"><span class="n">5</span><div><b>Read in ID, write in WB, same cycle.</b> Separate ports, so no structural
          conflict. The write lands on the edge AFTER the read, so ID would see the OLD value: lesson 27 adds a WB&rarr;ID bypass in
          <span class="mono">cpu_pipe</span> (not in <span class="mono">regfile</span>: in single-cycle that is a combinational loop).</div></div>
        <div class="rule"><span class="n">6</span><div><b>Cancel = turn into NOP.</b> Reset, a bubble and a flush all mean:
          <span class="mono">reg_we = 0</span>, <span class="mono">mem_we = 0</span>, no jump.</div></div>
      </div>
    </div>
  </section>
  {foot(3)}
</div>"""

    # ---------------- page 4: hazards ----------------
    # data hazard
    dg = pipe_grid([
        ("0x00", "addi t0, x0, 5", flow(1, extra={5: ("WB", "s-WB hot")})),
        ("0x04", "add  t1, t0, t0", flow(2, extra={3: ("ID", "s-ID hot")})),
    ], 6)
    dg_nop = pipe_grid([
        ("0x00", "addi t0, x0, 5", flow(1, extra={5: ("WB", "s-WB hot")})),
        ("", "nop × 3", {2: ("·", "bub"), 3: ("·", "bub"), 4: ("·", "bub")}),
        ("0x10", "add  t1, t0, t0", flow(5, extra={6: ("ID", "s-ID hot")})),
    ], 10)
    lu = pipe_grid([
        ("", "lw   t0, 0(a0)", flow(1, extra={4: ("MEM", "s-MEM hot")})),
        ("", "add  t1, t0, t0", {2: ("IF", "s-IF"), 3: ("ID", "s-ID"), 4: ("ID", "s-ID"), 5: ("EX", "s-EX hot"),
                                 6: ("MEM", "s-MEM"), 7: ("WB", "s-WB")}),
        ("", "  bubble", {4: ("·", "bub"), 5: ("·", "bub"), 6: ("·", "bub")}),
    ], 7)
    ctl = pipe_grid([
        ("0x08", "beq (taken)", flow(1, extra={3: ("EX", "s-EX hot")})),
        ("0x0C", "next", {2: ("IF", "fl"), 3: ("ID", "fl")}),
        ("0x10", "next + 1", {3: ("IF", "fl")}),
        ("target", "target", flow(4)),
    ], 8)

    page4 = f"""
<div class="page">
  <h2>Hazards <small>when the overlap gives a wrong answer · red outline = where the value is written / needed</small></h2>

  <div class="hz"><h3>{stag("ID")}<span>Structural</span><span class="cost">cost 0 · already solved</span></h3>
    <p>Two stages want the same hardware in the same cycle. Here IF uses <span class="mono">imem</span> and MEM uses
    <span class="mono">dmem</span> (Harvard), and the regfile has separate read and write ports. Nothing to do.</p></div>

  <div class="hz"><h3>{stag("EX")}<span>Data (read after write)</span><span class="cost">lesson 27 · forwarding → cost 0</span></h3>
    <div class="cols">
      <div>{dg}
        <p style="margin-top:1.4mm"><b>add</b> reads t0 in ID at c3, but <b>addi</b> writes it only at the end of c5. Until lesson 27
        (and in <span class="mono">test_pipe_b</span>) this is solved with <b>3 NOPs</b> between dependent instructions.</p>
        {dg_nop}</div>
      <div><p>The value exists much earlier: it is in <span class="mono">ex_mem.alu_out</span> one cycle after EX.
        Forwarding is a MUX in front of the ALU that takes the newest copy:</p>
<pre class="code"><span class="c">// EX: detection (same for b / rs2)</span>
assign ex_hit_a = ex_mem.reg_we &amp;&amp; (ex_mem.rd != 5'd0)
                &amp;&amp; (ex_mem.rd == id_ex.rs1);
assign wb_hit_a = mem_wb.reg_we &amp;&amp; (mem_wb.rd != 5'd0)
                &amp;&amp; (mem_wb.rd == id_ex.rs1);
always_comb begin                 <span class="c">// newest wins</span>
    if (ex_hit_a)      fwd_a_val = ex_mem.alu_out;
    else if (wb_hit_a) fwd_a_val = wb_data;
    else               fwd_a_val = id_ex.rs1_data;
end
<span class="c">// ID: WB writes what ID reads, same cycle</span>
assign id_rs1_val = (wb_we &amp;&amp; (wb_rd != 5'd0)
    &amp;&amp; (wb_rd == rs1)) ? wb_data : rs1_data;</pre>
        <p style="margin-top:1.2mm"><b>Consumers:</b> <span class="mono">alu_a</span> default, <span class="mono">alu_b</span>,
        <span class="mono">lt</span>/<span class="mono">ltu</span>, store data <span class="mono">ex_mem.rs2_data</span>;
        <span class="mono">id_ex.rs*_data &lt;= id_rs*_val</span>.
        From WB forward <span class="mono">wb_data</span> (what is written: LW &rarr; <span class="mono">ld_data</span>, not the address).
        Distance 1 &rarr; EX/MEM, 2 &rarr; MEM/WB, 3 &rarr; ID bypass, 4+ &rarr; regfile.</p></div>
    </div></div>

  <div class="hz"><h3>{stag("MEM")}<span>Load-use</span><span class="cost">lesson 28 · stall 1 cycle</span></h3>
    <div class="cols">
      <div>{lu}</div>
      <div><p>A load has its data only at the end of MEM (c4), but the next instruction needs it at the start of EX (c4).
        <b>Forwarding is a wire, not a time machine.</b> Detect in ID (last chance), then for one cycle:
        hold PC and IF/ID, put a bubble into ID/EX. Next cycle the load is in WB and <span class="mono">wb_hit</span>
        forwards <span class="mono">wb_data</span> (lesson 27 code, unchanged).</p>
<pre class="code"><span class="c">// IF: declared here, IF uses it before ID</span>
logic stall;
.pc_next (stall ? pc_cur : pc_next),   <span class="c">// u_pc: hold</span>
end else if (!stall) begin             <span class="c">// if_id: hold</span>
<span class="c">// ID: load in EX and its rd is read here</span>
assign stall = (id_ex.wb_sel == 2'd1) &amp;&amp; (id_ex.rd != 5'd0)
    &amp;&amp; ((id_ex.rd == rs1) || (id_ex.rd == rs2));
if (rst || flush || stall) begin       <span class="c">// id_ex: bubble =</span>
    id_ex.reg_we &lt;= 1'b0; ...          <span class="c">// 6 control fields</span></pre>
        <p style="margin-top:1.2mm">Compare register <b>numbers</b> (<span class="mono">rs1</span>), not values (<span class="mono">rs1_data</span>).
        No assignment in <span class="mono">always_ff</span> = hold (FF with enable). ID/EX is not held: the load must move on.
        I-type has no rs2 (bits = imm) &rarr; sometimes an extra stall: slower, never wrong.</p></div>
    </div></div>

  <div class="hz"><h3>{stag("EX")}<span>Control</span><span class="cost">lesson 29 · flush, 2 cycles per taken jump</span></h3>
    <div class="cols">
      <div>{ctl}
        <p style="margin-top:1.4mm">Predict not-taken: IF keeps fetching <span class="mono">pc + 4</span>. The jump is decided in EX (c3),
        so ID and IF hold wrong-path instructions. Not taken = no cost.</p></div>
      <div>
<pre class="code">logic flush;                           <span class="c">// IF: declared early</span>
if (rst || flush)                      <span class="c">// if_id: throw away</span>
    if_id.instr[11:0] &lt;= 12'h013;      <span class="c">// ADDI x0 = NOP</span>
if (rst || flush || stall) begin       <span class="c">// id_ex: clear 6 ctrl</span>
assign flush = take_branch | id_ex.jump | id_ex.jalr;</pre>
        <p style="margin-top:1.2mm"><b>Stall holds, flush throws away:</b> IF/ID needs its own branch, ID/EX bubbles either way.
        PC untouched (already <span class="mono">pc_target</span>). Never meet: stall = load in EX, flush = jump in EX.
        <b>30b:</b> only 19 control FFs cleared, data don't care: 81.3 &rarr; 90.5 MHz.</p></div>
    </div></div>
  {foot(4)}
</div>"""

    # ---------------- page 5: CPI, comparison, checklist, roadmap ----------------
    page5 = f"""
<div class="page">
  <section class="block">
    <h2>CPI <small>cycles per instruction, after the pipe is full</small></h2>
    <div class="two">
      <div class="note" style="font-size:8pt">
        <div class="big mono" style="margin-bottom:1.5mm">cycles = N + 4 + S + 2·J</div>
        <b>N</b> instructions, <b>4</b> to fill the pipe, <b>S</b> load-use stalls, <b>J</b> taken branches and jumps.
        CPI = cycles / N. Single-cycle has CPI = 1 but a 4× longer clock.<br><br>
        <b>Measured</b> (<span class="mono">tb_cpu_pipe_sort</span>, bubble sort): N = 101, S = 9 (LW t5 &rarr; BGE, 3 &times; 3),
        J = 24 &rarr; 162 by formula, 161 until <span class="mono">done</span> enters EX. CPI &asymp; 1.59;
        at 8 ns (paper) &times;2.5. <b>Basys 3:</b> 161 / 90.5 MHz = 1.78 &micro;s vs 101 / 94.4 MHz = 1.07 &micro;s:
        the pipeline is 1.66&times; <b>slower</b> (it would need 150 MHz). Flushes are 48 of the 61 extra cycles (79%).<br>
        <b>Scheduling:</b> move <span class="mono">j++</span> between LW and BGE &rarr; S = 0, 152 cycles, CPI 1.50.
      </div>
      <div>{simple_table(["", "Single-cycle", "Pipeline"], [
            ("Clock", "sum of stages", "slowest stage"),
            ("CPI", "1", "1 + stalls + flushes"),
            ("Fmax (Basys 3)", "94.4 MHz", "90.5 MHz"),
            ("LUT / FF", "589 / 34", "1062 / 449"),
            ("Hazards", "none", "data, load-use, control"),
            ("Files", m("cpu.sv · tag v1-single-cycle"), m("cpu_pipe.sv")),
        ], "cmp")}</div>
    </div>
  </section>

  <section class="block">
    <h2>Bug checklist <small>look here first when a pipeline test fails</small></h2>
    {simple_table(["Symptom", "Usual cause", "Fix"], [
        ("Branch / AUIPC target off by 8", m("pc_cur") + " used in EX", m("id_ex.pc")),
        ("JAL writes the wrong link value", m("pc_plus4") + " (IF) in WB", m("id_ex.pc + 4") + " carried to WB"),
        ("Result lands in the wrong register", "rd taken from " + m("if_id.instr[11:7]"), "carry rd: id_ex → ex_mem → mem_wb"),
        ("Writes happen during reset / flush", "card reset leaves reg_we or mem_we = 1", m("'0") + " or NOP instr"),
        ("Value correct 3 instr later, not 1–2", "no forwarding yet", "NOPs (26b) / forwarding (27)"),
        ("Use right after LW gets the address", "WB forwards " + m("mem_wb.alu_out"), "forward " + m("wb_data")),
        ("Back-to-back writes: old value used", "WB checked before EX/MEM", "EX/MEM first (newest)"),
        ("x0 becomes non-zero via forwarding", "missing " + m("rd != 0"), "add the guard"),
        ("Use right after LW: value of the address / x", "no stall, or rs1_data compared", m("stall") + " on reg numbers (28)"),
        ("Instruction after a stall vanishes", "IF/ID not held", m("else if (!stall)") + " on if_id"),
        ("Program runs code after a taken jump", "no flush yet", "NOPs after jumps (26b) / flush (29)"),
        ("Wrong-path jump still redirects the PC", "IF/ID not flushed (only ID/EX)", m("else if (flush)") + " on if_id, NOP instr"),
        ("Flush one cycle early, link reg lost", m("jump") + " / " + m("jalr") + " of ID used", m("id_ex.jump | id_ex.jalr")),
        ("Stalls forever after a partial bubble", m("wb_sel") + " kept = 1, stall sees the load again", "clear " + m("wb_sel") + " too"),
        ("tb fails by one cycle", "counted the stage, not the cycle", "draw the instr × cycle grid"),
    ])}
  </section>

  <section class="block">
    <h2>Roadmap <small>lessons 26–30</small></h2>
    {simple_table(["Lesson", "Adds", "Test"], [
        ("26a ✓", "pipe_pkg, IF/ID, ID/EX, EX stage", m("tb_cpu_pipe_a") + " · 22 checks, cards cycle by cycle"),
        ("26b ✓", "EX/MEM, MEM/WB, MEM, WB → regfile", m("tb_cpu_pipe_b") + " · 13 checks, 3-instr gaps, NOPs after jumps"),
        ("27 ✓", "forwarding + WB→ID bypass", m("tb_cpu_pipe_c") + " · 13 checks, no data NOPs; synth 48 warnings"),
        ("28 ✓", "load-use stall: hold + bubble", m("tb_cpu_pipe_d") + " · 14 checks, lw right before use, stalls == 4"),
        ("29 ✓", "flush: NOP into IF/ID, ID/EX", m("tb_cpu_pipe_e") + " · 15 checks, no NOPs after jumps, flushes == 5"),
        ("30a ✓", "CPI on bubble sort, scheduling", m("tb_cpu_pipe_sort") + " · 8 checks, 9 stalls, 24 flushes, CPI 1.59"),
        ("30b ✓", "Basys 3: Fmax vs single-cycle, fanout fixes", m("fpga/build.tcl") + " · 94.4 vs 90.5 MHz (was 81.3)"),
    ])}
  </section>
  {foot(5)}
</div>"""

    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>Pipeline reference · arielhuna/riscv-cpu</title><style>{CSS}</style></head>
<body>{page1}{page2}{page3}{page4}{page5}</body></html>"""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--html", action="store_true", help="write the .html only")
    args = ap.parse_args()

    html_path = HERE / "pipeline_reference.html"
    pdf_path = HERE / "pipeline_reference.pdf"
    html_path.write_text(build_html(), encoding="utf-8")
    print(f"wrote {html_path.relative_to(ROOT)}")
    if args.html:
        return

    browser = find_browser()
    if not browser:
        sys.exit("no Chrome/Edge found: open the .html and print it to PDF (margins: none)")
    subprocess.run([browser, "--headless", "--disable-gpu", "--no-pdf-header-footer", "--no-sandbox",
                    f"--print-to-pdf={pdf_path}", html_path.as_uri()],
                   check=True, capture_output=True)
    print(f"wrote {pdf_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
