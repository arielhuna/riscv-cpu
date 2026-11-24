# Program the Basys 3 over USB (JTAG)
# Run from build/:
#   vivado -mode batch -nojournal -nolog -source ..\fpga\program.tcl -tclargs top_pipe.bit

set bit top_pipe.bit
if {$argc > 0} { set bit [lindex $argv 0] }

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a35t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "program: $bit -> [get_property NAME $dev] done"
close_hw_manager
