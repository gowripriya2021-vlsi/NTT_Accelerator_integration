# these are default values. Change only if you know what you are doing!!
set tech_size 65
set freq_mhz  100
set top mk_add_sub_sp_instance
set max_uncert_factor  0.1
set input_delay_factor 0.3
set output_delay_factor 0.3
set loadvalue 0.00806
set enable_clockgating true
set derate_value 1.10

# change below as per your needs
set verilog_dir <absolute_path_to_verilog_folder>
set retime_list {<list of modules to be retimed>}
#set_attr auto_super_thread false
#set_attr super_thread_debug_directory {{./}}
#set_attr super_thread_debug_jobs true
set clk_port CLK

set report_dir rpt
set output_dir output
