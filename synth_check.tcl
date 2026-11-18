# Elaboration-only synthesis check (no implementation, no bitstream)
# Run from build/:
#   vivado -mode batch -nojournal -nolog -source ..\synth_check.tcl                      (top = cpu)
#   vivado -mode batch -nojournal -nolog -source ..\synth_check.tcl -tclargs cpu_pipe    (top = cpu_pipe)

set top cpu
if {$argc > 0} { set top [lindex $argv 0] }
puts "synth_check: top = $top"

# Packages first, then the rest of the RTL
read_verilog -sv [glob ../rtl/pkg/*.sv]
read_verilog -sv [glob ../rtl/*.sv]

# Basys 3 part: Artix-7 XC7A35T, CPG236 package, speed grade -1
synth_design -rtl -top $top -part xc7a35tcpg236-1
