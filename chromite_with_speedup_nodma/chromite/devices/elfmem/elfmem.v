`verilator_config
lint_off -rule WIDTH
lint_off -rule CASEINCOMPLETE
lint_off -rule STMTDLY
lint_off -rule UNSIGNED
lint_off -rule CMPCONST
`verilog

import "DPI-C" function longint unsigned load_elf(longint unsigned base, longint unsigned size, 
                string debug);
import "DPI-C" function longint unsigned read_f(longint unsigned ptr, longint unsigned addr);
import "DPI-C" function void write_f(longint unsigned ptr, longint unsigned addr, 
                longint unsigned val, longint unsigned wr_sz);

