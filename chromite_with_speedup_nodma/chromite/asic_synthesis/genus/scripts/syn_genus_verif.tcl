# see LICENSE.incore

#=====================================================================================
## This script is used to perform checks to determine synthesis run was error free 
#=====================================================================================

set outFile [open ./${report_dir}/synthesis_checks.rpt w]
applet load get_logic_levels

puts $outFile "SYNTHESIS RUN CHECKS SUMMARY\n"
puts $outFile "\n---------------------------------------------------------------------------------------"
puts $outFile "CURRENT DESIGN   : $top"
puts $outFile "SYNTHESIS RUN BY : [exec whoami]"
puts $outFile "DATE and TIME    : [exec date +%d_%b_%y-%H_%M_%S]"
puts $outFile "---------------------------------------------------------------------------------------\n\n"
puts $outFile "Target Freq: $freq_mhz MHz"
set elab_flops      "Number of flipflops in elaboration      = ${num_flipflops_elab}"
set final_flops     "Final Number of flipflops in Final      = ${num_flipflops_final}"
set non_reset_flops "Number of non_reset_flops               = [expr [sizeof_collection [all_registers -flops]]- [sizeof_collection [all_registers -async_pins] ]]"
set latches         "Number of latches                       = [sizeof_collection [all_registers -latches]]"
set level_sensitive "Number of level_sensitive registers     = [sizeof_collection [all_registers -level_sensitive]]"
set neg_edge_flops  "Number of negative edge triggered flops = [sizeof_collection [all_registers -edge_triggered -fall_clock [all_clocks]]]"

puts $outFile "$elab_flops"
puts $outFile "$final_flops"
puts $outFile "$non_reset_flops"
puts $outFile "$latches"
puts $outFile "$level_sensitive"
puts $outFile "$neg_edge_flops"
close $outFile

report timing > /tmp/report_timing
set slack [exec grep "Timing slack :" /tmp/report_timing]
set start_point [exec grep "Start-point" /tmp/report_timing | awk {{print $3}} ]
set end_point [exec grep "End-point" /tmp/report_timing | awk {{print $3}} ]
redirect /tmp/report_timing {get_logic_levels "report timing -from $start_point -to $end_point"}
set total_lol [exec grep "Logic Levels" /tmp/report_timing | awk {{print $4}}]



report_timing -worst 1 -cost_group f2f -num_paths 1 -user_derate > /tmp/report_timing 
if {[catch {exec grep "Timing slack :" /tmp/report_timing}]} {
    set f2f_slack "Timing slack: No paths"
    set f2f_lol "0"
} else {
    set  f2f_slack [exec grep "Timing slack :" /tmp/report_timing]
    set start_point [exec grep "Start-point" /tmp/report_timing | awk {{print $3}} ]
    set end_point [exec grep "End-point" /tmp/report_timing | awk {{print $3}} ]
    redirect /tmp/report_timing {get_logic_levels "report timing -from $start_point -to $end_point"}
    set f2f_lol [exec grep "Logic Levels" /tmp/report_timing | awk {{print $4}}]
}
report_timing -worst 1 -cost_group i2f -num_paths 1 -user_derate > /tmp/report_timing 
if {[catch {exec grep "Timing slack :" /tmp/report_timing}]} {
    set i2f_slack "Timing slack: No paths"
    set i2f_lol "0"
} else {
    set  i2f_slack [exec grep "Timing slack :" /tmp/report_timing]
    set start_point [exec grep "Start-point" /tmp/report_timing | awk {{print $3}} ]
    set end_point [exec grep "End-point" /tmp/report_timing | awk {{print $3}} ]
    redirect /tmp/report_timing {get_logic_levels "report timing -from $start_point -to $end_point"}
    set i2f_lol [exec grep "Logic Levels" /tmp/report_timing | awk {{print $4}}]
}
report_timing -worst 1 -cost_group f2o -num_paths 1 -user_derate > /tmp/report_timing 
if {[catch {exec grep "Timing slack :" /tmp/report_timing}]} {
    set f2o_slack "Timing slack: No paths"
    set f2o_lol "0"
} else {
    set  f2o_slack [exec grep "Timing slack :" /tmp/report_timing]
    set f2o_lol "Unable to calculate in script"
}
report_timing -worst 1 -cost_group i2o -num_paths 1 -user_derate > /tmp/report_timing 
if {[catch {exec grep "Timing slack :" /tmp/report_timing}]} {
    set i2o_slack "Timing slack: No paths"
    set i2o_lol "0"
} else {
    set  i2o_slack [exec grep "Timing slack :" /tmp/report_timing]
    set start_point [exec grep "Start-point" /tmp/report_timing | awk {{print $3}} ]
    set end_point [exec grep "End-point" /tmp/report_timing | awk {{print $3}} ]
    redirect /tmp/report_timing {get_logic_levels "report timing -from $start_point -to $end_point"}
    set i2o_lol [exec grep "Logic Levels" /tmp/report_timing | awk {{print $4}}]
}


report gates > /tmp/report_timing
set tot_area [exec grep "total" /tmp/report_timing | head -1 | awk {{print $1 " area = " $3 }}]
set seq_area [exec grep "sequential" /tmp/report_timing | awk {{print $1 " area = " $3 }}]
if {[catch {exec grep "inverter" /tmp/report_timing}]} {
    set inverter_area "0"
} else {
    set  inverter_area [exec grep "inverter" /tmp/report_timing | awk {{print $3}}]
}
if {[catch {exec grep "buffer" /tmp/report_timing}]} {
    set buffer_area "0"
} else {
    set  buffer_area [exec grep "buffer" /tmp/report_timing | awk {{print $3}}]
}
if {[catch {exec grep "logic" /tmp/report_timing}]} {
    set logic_area "0"
} else {
    set  logic_area [exec grep "logic" /tmp/report_timing | awk {{print $3}}]
}
if {[catch {exec grep "clock_gating_integrated_cell" /tmp/report_timing}]} {
    set ckln_cell_area "0"
} else {
    set  ckln_cell_area [exec grep "clock_gating_integrated_cell" /tmp/report_timing | awk {{print $3}}]
}
set  combo_area  "Combinational area = [expr $inverter_area + $buffer_area + $logic_area + $ckln_cell_area]"
report power > /tmp/report_timing
set  leakage_power "Leakage Power(W) = [exec grep "total" /tmp/report_timing | awk {{print  $2 }}]"
set  dynamic_power "Dynamic Power(W) = [exec grep "total" /tmp/report_timing | awk {{print  $4 }}]"
set  total_power   "Total Power(W) = [exec grep "total" /tmp/report_timing | awk {{print  $5 }}]"


set outFile [open ./${report_dir}/synthesis_checks.rpt a]
puts $outFile "Worst $slack. LOL: $total_lol"
puts $outFile "F2F $f2f_slack. LOL: $f2f_lol"
puts $outFile "I2F $i2f_slack. LOL: $i2f_lol"
puts $outFile "F2O $f2o_slack. LOL: $f2o_lol"
puts $outFile "I2O $i2o_slack. LOL: $i2o_lol"
puts $outFile "$tot_area um²"
puts $outFile "$seq_area um²"
puts $outFile "$combo_area um²"
puts $outFile "$leakage_power"
puts $outFile "$dynamic_power"
puts $outFile "$total_power"
#puts $outFile "$black_box"

puts $outFile "\n---------------------------------------------------------------------------------------"
puts $outFile "                          CHECK DESIGN REPORT SUMMARY                                         "
puts $outFile "---------------------------------------------------------------------------------------"
close $outFile

check_design $top -all > /tmp/report_timing
exec grep -A27 "Summary" /tmp/report_timing | grep "Unresolved" >> ./${report_dir}/synthesis_checks.rpt
exec grep -A27 "Summary" /tmp/report_timing | grep "Empty" >> ./${report_dir}/synthesis_checks.rpt
exec grep -A27 "Summary" /tmp/report_timing | grep "Unloaded" >> ./${report_dir}/synthesis_checks.rpt
exec grep -A27 "Summary" /tmp/report_timing | grep "Undriven" >> ./${report_dir}/synthesis_checks.rpt
exec grep -A27 "Summary" /tmp/report_timing | grep "Multidriven" >> ./${report_dir}/synthesis_checks.rpt

set outFile [open ./${report_dir}/synthesis_checks.rpt a]
puts $outFile "\n---------------------------------------------------------------------------------------"
puts $outFile "                           LINT REPORT SUMMARY                                         "
puts $outFile "---------------------------------------------------------------------------------------"
close $outFile

report timing -lint > /tmp/report_timing
exec grep -A20 "Lint summary" /tmp/report_timing >> ./${report_dir}/synthesis_checks.rpt
exec perl -pi -e "s/Â//g" ./${report_dir}/synthesis_checks.rpt
