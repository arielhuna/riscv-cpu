# Full Basys 3 build: synthesis, place & route, timing, bitstream
# Run from build/:
#   vivado -mode batch -nojournal -nolog -source ..\fpga\build.tcl -tclargs 1 > build_pipe.log     (cpu_pipe)
#   vivado -mode batch -nojournal -nolog -source ..\fpga\build.tcl -tclargs 0 > build_single.log   (cpu)

set pipe 1
if {$argc > 0} { set pipe [lindex $argv 0] }
if {$pipe} { set name pipe } else { set name single }
puts "build: PIPE = $pipe ($name)"

# Sources: packages first, then RTL, then the board top
read_verilog -sv [glob ../rtl/pkg/*.sv]
read_verilog -sv [glob ../rtl/*.sv]
read_verilog -sv ../fpga/top_basys3.sv
read_xdc ../fpga/basys3.xdc

# Synthesis -> netlist of LUTs and FFs
synth_design -top top_basys3 -part xc7a35tcpg236-1 -generic PIPE=$pipe

# Implementation: optimize, place, route
opt_design
place_design
route_design

# Reports and bitstream
report_utilization    -file util_$name.rpt
report_timing_summary -file timing_$name.rpt
write_bitstream -force top_$name.bit

# WNS = slack of the worst path; its requirement = the clock period it was timed at
set path [get_timing_paths -max_paths 1 -nworst 1 -setup]
set wns  [get_property SLACK $path]
set req  [get_property REQUIREMENT $path]
puts "build: period = $req ns, WNS = $wns ns, Fmax = [format %.1f [expr {1000.0 / ($req - $wns)}]] MHz"