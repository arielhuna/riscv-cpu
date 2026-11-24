# rvtests: official riscv-tests (rv32ui) for riscv-cpu

The 40 user-level RV32I tests from [riscv-tests](https://github.com/riscv-software-src/riscv-tests)
(commit `3df703c`), compiled for this CPU. `fence_i` and `ma_data` are skipped
(self-modifying code and misaligned access are not supported).

| File | What |
|---|---|
| `env/riscv_test.h` | Minimal test environment: no CSRs or traps. Pass writes 1 to `tohost` (0x3FC), fail writes `(test_case << 1) \| 1` |
| `link.ld` | Harvard layout: code from 0x0 in `imem`, data from 0x0 in `dmem` |
| `build.py` | Compiles every test and writes `hex/<name>.hex` (imem) and `hex/<name>.data.hex` (dmem), plus `list.txt` |
| `hex/` | Generated: 40 x 2 files, ready for `$readmemh` |

Rebuild (needs `riscv64-unknown-elf-gcc`, lesson 35):

```
git clone https://github.com/riscv-software-src/riscv-tests
python3 rvtests/build.py riscv-tests
```
