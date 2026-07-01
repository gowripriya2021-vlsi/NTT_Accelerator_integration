# ******* not to be hacked ********
set tech_size 65
set wireloadmodel <wire-load-model>
set wireloadmode top
set library_path <path to your .lib files>
set buffcell   <buffer cells to be used>
set ckbuffcell <clock buffer cells to be used>
set tielow_cell_name <cellname for tie-low>
set tiehigh_cell_name <cellname for tie-high>

set flop_prefixes {<list of prefixes for all flip-flops. eg SD* DF*>}
set scanflop_prefixes {< list of prefixes for all scan flops. eg: SDFD* SDFQD*>}
set dont_use_list {<list of cells that should not be used>}

set avoid_clockgating_list {<list of cells to avoid during clock-gating>}
set clockgating_cell_to_use <cell name of clockgating cell>
