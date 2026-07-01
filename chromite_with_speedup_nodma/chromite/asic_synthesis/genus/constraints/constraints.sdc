set_time_unit -nanoseconds 1.0
set clk_period [expr 1000.0/${freq_mhz}]
set clkp ${clk_period} 

create_clock -name clk -p $clkp [get_ports $clk_port]

set_clock_uncertainty [expr ($max_uncert_factor*$clkp)] -setup [all_clocks]

set_input_delay   [expr ($input_delay_factor*$clkp)]      -clock clk [all_inputs ];
set_output_delay  [expr ($output_delay_factor*$clkp)]      -clock clk [all_outputs];

set_timing_derate -late -data $derate_value $top;        # Setting derate to 10%
set_load         -pin_load $loadvalue [all_outputs]
set_max_transition 0.55 [current_design]
set_ideal_network [get_ports $clk_port]
