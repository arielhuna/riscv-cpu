# Full Basys 3 build: synthesis, place & route, timing, bitstream
# Run from build/:
#   vivado -mode batch -nojournal -nolog -source ..\fpga\build.tcl -tclargs 1 10 > build_pipe.log     (cpu_pipe)
#   vivado -mode batch -nojournal -nolog -source ..\fpga\build.tcl -tclargs 0 10 > build_single.log   (cpu)
# Arg 1: PIPE (default 1). Arg 2: CLK_DIV, CPU clock = 1000 / CLK_DIV MHz (default 15)

set pipe 1
if {$argc > 0} { set pipe [lindex $argv 0] }
if {$pipe} { set name pipe } else { set name single }

set div 15
if {$argc > 1} { set div [lindex $argv 1] }
puts "build: PIPE = $pipe ($name), CLK_DIV = $div"

# Sources: packages first, then RTL, then the board top
read_verilog -sv [glob ../rtl/pkg/*.sv]
read_verilog -sv [glob ../rtl/*.sv]
read_verilog -sv ../fpga/top_basys3.sv
read_xdc ../fpga/basys3.xdc

# Synthesis -> netlist of LUTs and FFs
synth_design -top top_basys3 -part xc7a35tcpg236-1 -generic PIPE=$pipe -generic CLK_DIV=$div

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
