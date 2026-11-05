# Elaboration-only synthesis check for the CPU (no implementation, no bitstream)
# Run from build/:  vivado -mode batch -nojournal -nolog -source ..\synth_check.tcl

# Packages first, then the rest of the RTL
read_verilog -sv [glob ../rtl/pkg/*.sv]
read_verilog -sv [glob ../rtl/*.sv]

# Basys 3 part: Artix-7 XC7A35T, CPG236 package, speed grade -1
synth_design -rtl -top cpu -part xc7a35tcpg236-1