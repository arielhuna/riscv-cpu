# lessons

Early Verilog exercises from the first lessons, kept for reference. They are not part of the CPU and are not picked up by `sim.bat`, `run_all.bat` or `synth_check.tcl` (those only read `rtl/` and `tb/`).

| File | What it is |
|---|---|
| `ram16x8.sv` | 16 x 8 RAM, loaded from `mem.hex` |
| `tb_ram16x8.sv` | waveform testbench for it (not self-checking) |
| `tb_alu.sv` | first ALU testbench, prints with `$monitor` (replaced by `tb/tb_alu_self.sv`) |
| `mem.hex` | initial contents for `ram16x8` |

To run one, compile it by hand from `build/`, for example:

```
xvlog --sv ..\rtl\pkg\alu_pkg.sv ..\rtl\alu.sv ..\lessons\tb_alu.sv
xelab tb_alu -s tb_alu_sim
xsim tb_alu_sim -runall
```
