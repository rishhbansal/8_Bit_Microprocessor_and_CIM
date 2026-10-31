package require openlane
source /openlane/designs/cpu_core/runs/run_cim/config.tcl

# Restore state to right after Step 21 (Fill Insertion) + CIM Global Route Guide
set ::env(TERMINAL_OUTPUT) "/dev/stdout"
set ::env(CURRENT_INDEX) 21
set ::env(CURRENT_ODB) /openlane/designs/cpu_core/runs/run_cim/tmp/routing/21-fill.odb
set ::env(CURRENT_DEF) /openlane/designs/cpu_core/runs/run_cim/tmp/routing/21-fill.def
set ::env(CURRENT_NETLIST) /openlane/designs/cpu_core/runs/run_cim/tmp/routing/21-fill.nl.v
set ::env(CURRENT_GUIDE) /openlane/designs/cpu_core/runs/run_cim/tmp/routing/18-global.guide

puts ">>> (1/3) Running TritonRoute Detailed Routing with CIM guide..."
detailed_routing

puts ">>> (2/3) Streaming out GDSII with Magic..."
run_magic

puts ">>> (3/3) Running Magic DRC Signoff..."
run_magic_drc

puts ">>> (SUCCESS) CIM Routing -> GDSII -> DRC Signoff Complete!"
