#!/usr/bin/env python3
"""Build riscv-tests rv32ui for riscv-cpu: one .hex (imem) and one .data.hex (dmem) per test.
Needs riscv64-unknown-elf-gcc and a riscv-tests checkout:
    python3 rvtests/build.py /path/to/riscv-tests
"""
import pathlib, subprocess, sys

HERE  = pathlib.Path(__file__).resolve().parent
TESTS = pathlib.Path(sys.argv[1]) / "isa"
OUT   = HERE / "hex"
SKIP  = {"fence_i", "ma_data"}          # self-modifying code / misaligned access: not supported
CC    = "riscv64-unknown-elf-"

def words(binfile):
    data = binfile.read_bytes()
    data += b"\0" * (-len(data) % 4)
    return [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]

OUT.mkdir(exist_ok=True)
names = []
for src in sorted((TESTS / "rv32ui").glob("*.S")):
    name = src.stem
    if name in SKIP:
        continue
    elf = OUT / f"{name}.elf"
    subprocess.run([CC + "gcc", "-march=rv32i", "-mabi=ilp32", "-nostdlib", "-nostartfiles", "-static",
                    "-T", str(HERE / "link.ld"), "-Wl,--no-check-sections",
                    "-I", str(HERE / "env"), "-I", str(TESTS / "macros" / "scalar"),
                    str(src), "-o", str(elf)], check=True)
    for sec, suffix in ((".text", ".hex"), (".data", ".data.hex")):
        binf = OUT / f"{name}{suffix}.bin"
        subprocess.run([CC + "objcopy", "-O", "binary", "-j", sec, str(elf), str(binf)], check=True)
        w = words(binf) or [0]
        (OUT / f"{name}{suffix}").write_text("".join(f"{x:08X}\n" for x in w))
        binf.unlink()
    elf.unlink()
    names.append(name)

(HERE / "list.txt").write_text("".join(n + "\n" for n in names))
print(f"{len(names)} tests -> {OUT}")
