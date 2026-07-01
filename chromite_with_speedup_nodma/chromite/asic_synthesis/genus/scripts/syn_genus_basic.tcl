# see LICENSE.incore
#=====================================================================================
#This is a basic script to run synthesis on Genus 
#Add required libraries to lib_list incase design contains memories
#This script :
    #Uses WLM for synthesis
    #Should NOT be used for Genus Physical
    #Preserves hierarchy of all instances
    #Uses 10% derate (can be over-written by constraint file)
#=====================================================================================

#=====================================================================================
# Procedures
#=====================================================================================
  #query_obj is an utility function to print a list (for eg. Flop list) into a file
  #It is NOT important for synthesis
  proc query_obj {in_col file_name} {

     set fileid [open ./${report_dir}/${file_name}_list.txt w]
     foreach_in_collection ff $in_col {
        set obj_name [get_attribute name $ff]
        puts $fileid $obj_name
     }

     close $fileid
  }

#=====================================================================================
# Library settings
#=====================================================================================
  set_db common_ui false
  source $pd_input_tcl.tcl
  source $user_tcl
  set_attribute design_process_node $tech_size

  #Make ${report_dir} and ${output_dir} directories if they don't exist
  if {![file exists ${report_dir}]} { file mkdir ${report_dir} }
  if {![file exists ${output_dir}]} { file mkdir ${output_dir} }

  #Set Library list
  set lib_list [list $library_path]
  set_attr -q library     ${lib_list}

#=====================================================================================
# Initial
#=====================================================================================
  set stage init

  set_attr -q hdl_unconnected_input_port_value 	none / ; #default is 0
  set_attr -q hdl_undriven_output_port_value 	none / ; #default is 0
  set_attr -q hdl_undriven_signal_value 	none / ; #default is 0
  set_attr -q auto_ungroup none;  #default value is both
  puts "SET STAGE INIT DONE"


#=====================================================================================
# RTL files
#=====================================================================================
  #Read RTL files. Example :
  set_attr -q hdl_error_on_blackbox true
  read_hdl -define BSV_ASYNC_RESET -define BSV_ASYNC_RESET -define BSV_RESET_FIFO_ARRAY -define BSV_RESET_FIFO_HEAD -define BSV_NO_INITIAL_BLOCKS [glob ${verilog_dir}/*.v]
#=====================================================================================
# Elaboration
#=====================================================================================
  set stage elaborate
  elaborate $top
  set num_flipflops_elab [sizeof_collection [all_registers -edge_triggered]]
  puts "Number of flipflops in elaboration = ${num_flipflops_elab}"
  query_obj [all_registers -edge_triggered] ff_${stage}

  uniquify $top
  check_design $top -unresolved > ${report_dir}/black_boxed.txt

#=====================================================================================
# General synthesis settings
#=====================================================================================
  set_attribute -q interconnect_mode wireload / ; #default is none
  set_wire_load_mode $wireloadmode
  if {[info exists wireloadmodel]}  {
    set_wire_load_model -name $wireloadmodel
  }

  reset_timing_derate

#=====================================================================================
# Constraints
#=====================================================================================
  #Ensure constraint file is present
  read_sdc ../constraints/constraints.sdc
  if {[info exists buffcell]}  {
    set_driving_cell -lib_cell $buffcell [all_inputs -no_clocks]
  }
  if {[info exists ckbuffcell]}   {
    set_driving_cell -lib_cell $ckbuffcell  [remove_from_collection [all_inputs] [all_inputs -no_clocks]]
  }

#=====================================================================================
# Dont-touch and dont-use cells
#    1) To enable usage of only scan flops
#    2) To disable usage of CSN flops
#    3) To disable usage of higher drive cells
#=====================================================================================
  #set all Flops as DONT use
  foreach pat $flop_prefixes {
  	set_attr -q avoid true [get_lib_cells ${pat}]
  	set_dont_use [get_lib_cells ${pat}] true
  }

  #Only enable use of Scan Flops
  foreach pat  $scanflop_prefixes {
  	set_attr -q avoid false [get_lib_cells ${pat}]
  	set_dont_use [get_lib_cells ${pat}] false
  }

  foreach pat $dont_use_list {
    set_attr -q avoid true [get_lib_cells ${pat}]
    set_dont_use [get_lib_cells ${pat}]
  }
#=====================================================================================
# Clock gating cell
#=====================================================================================
  if {$enable_clockgating == true} {
    foreach pat $avoid_clockgating_list {
      set_attr -q avoid true [get_lib_cells ${pat}]
    }
    puts "Setting clock gating cell for $top .."
    set cgcell $clockgating_cell_to_use
    catch {reset_attribute  dont_use   $cgcell }
    reset_attribute  avoid   $cgcell
    set_attr -q lp_clock_gating_cell $cgcell $top
  
    check_design $top -lib_lef_consistency > ${report_dir}/blib_lef_consistency.txt
  }
#=====================================================================================
# Retiming modules
#=====================================================================================
  if { [llength $retime_list] == 0} {
    set_attr -q retime false [find / -subdesign *]
  } else {
    foreach pat $retime_list {
      retime -prepare [find / -subdesign ${pat}]
      retime -min_delay [find / -subdesign ${pat}]
    }
  }

#=====================================================================================
# Set path groups
#=====================================================================================
  #
  define_cost_group -name f2f -design $top
  define_cost_group -name i2f -design $top
  define_cost_group -name f2o -design $top
  define_cost_group -name i2o -design $top
  #
  path_group -group f2f -from [all_registers]  -to [all_registers]
  path_group -group i2f -from [all_inputs -no_clocks]  -to [all_registers]
  path_group -group f2o -from [all_registers]  -to [all_outputs]
  path_group -group i2o -from [all_inputs -no_clocks]  -to [all_outputs]

#=====================================================================================
# Generic
#=====================================================================================
  set stage generic

  set_attr -q qos_report_power true  /
  set_attr -q dft_scan_map_mode force_all $top;                       #Force mapping of all flops to scan flops
  set_attr -q dft_connect_scan_data_pins_during_mapping ground  $top; #Connect scan data pins (SI) to 1'b0
  set_attr -q dft_connect_shift_enable_during_mapping tie_off $top;   #Connect scan enable pins (SE) to 1'b0
  #Adding additional attributes to optimize for power
  set_attr -q max_leakage_power 0.0  $top
  set_attr -q leakage_power_effort high

  #LP
  set_attr -q lp_multi_vt_optimization_effort high
  set_attr -q lp_optimize_dynamic_power_first true $top
  set_attr -q lp_power_optimization_weight 1 $top
  if {$enable_clockgating == true} {
    set_attr -q lp_clock_gating_infer_enable true /
    set_attr -q lp_insert_clock_gating true / ;                         #default is false
    set_attr -q lp_clock_gating_test_signal use_shift_enable $top
    set_attr -q lp_clock_gating_min_flops 8 $top
  }
  set_attr -q max_cpus_per_server 8
  set_attr -q optimize_merge_flops true  ;		              #default is true; setting to false for LEC easiness, hit on area

  set_attr -q optimize_constant_0_flops true ;
  set_attr -q optimize_constant_1_flops true ;
  set_attr -q boundary_optimize_constant_hpins true ;

  syn_gen

#=====================================================================================
# Map
#=====================================================================================
  set stage map
  syn_map
  if {[info exists tielow_cell_name]} {
    if {[info exists tiehigh_cell_name]} {
      insert_tiehilo_cells -lo $tielow_cell_name -hi $tiehigh_cell_name
    }
  }

#=====================================================================================
# Opt
#=====================================================================================
  set stage opt
  syn_opt

#=====================================================================================
# Final
#=====================================================================================
  set stage final
  syn_opt -incremental

#=====================================================================================
# Reports
#=====================================================================================
  set affix ${top}_${stage}
  write_db -all_root_attributes -to_file ${output_dir}/${affix}.db
  catch {report_timing -lint > ${report_dir}/check_timing.verbose.rpt}
  catch {write_hdl  > ${output_dir}/${affix}.v} err
  report_clock_gating > ${report_dir}/${affix}_clockgating.rpt
  report_qor > ${report_dir}/${affix}_qor.rpt
  report_area -depth 4 > ${report_dir}/${affix}_area.rpt
  report_power > ${report_dir}/${affix}_power_flat.rpt
  report_power > ${report_dir}/${affix}_power_hier.rpt
  report_timing -worst 1 -cost_group f2f -num_paths 20 -user_derate > ${report_dir}/${affix}_timing_f2f.rpt
  report_timing -worst 1 -cost_group i2f -num_paths 20 -user_derate > ${report_dir}/${affix}_timing_i2f.rpt
  report_timing -worst 1 -cost_group f2o -num_paths 20 -user_derate > ${report_dir}/${affix}_timing_f2o.rpt
  report_timing -worst 1 -cost_group i2o -num_paths 20 -user_derate > ${report_dir}/${affix}_timing_i2o.rpt
  report_timing -endpoints > ./${report_dir}/${affix}_timing_ep.txt
  report_timing -cost_group f2f -endpoints > ./${report_dir}/${affix}_timing_ep_f2f.txt
  report_timing -logic_levels 100 -cost_group f2f > ${report_dir}/${affix}_lol_f2f.rpt
  report_timing -logic_levels 100 -cost_group i2f > ${report_dir}/${affix}_lol_i2f.rpt
  report messages > ${report_dir}/${affix}_messages.rpt
  check_design -all > ./${report_dir}/check_design.rpt
  query_obj [all_registers -edge_triggered] ff_${stage}
  report_gates > ./${report_dir}/report_gates.rpt
  report_timing -verbose -lint > ./${report_dir}/check_timing_verbose_lint.txt
  report_timing -endpoints -slack_limit 1500 > ./${report_dir}/ep_final_slack.rpt
  report gates

  set num_flipflops_final [sizeof_collection [all_registers -edge_triggered]]
  set num_clock_gating_cells_final [sizeof_collection [get_cells -of_objects [get_pins  -of_objects [get_cells [all_registers ]] -filter "name==CPN"]]]
  source ../scripts/syn_genus_verif.tcl

#=====================================================================================
exit
#=====================================================================================
