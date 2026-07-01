# Compilation instructions
- This module uses a header only ELF parsing library called [ELFIO](https://github.com/serge1/ELFIO). Ensure that the repo is cloned.
- The following command should be used to compile with verilator.
```
.PHONY: link_verilator
link_verilator: ## Generate simulation executable using Verilator
	@echo $(CUST_VDIR)
	@echo $(CUST_CVSTR)
	@echo "Linking $(TOP_MODULE) using verilator"
	@mkdir -p $(BSVOUTDIR) obj_dir
	@echo "#define TOPMODULE V$(TOP_MODULE)_ed" > sim_main.h
	@echo '#include "V$(TOP_MODULE)_ed.h"' >> sim_main.h
	sed -f ./sed.txt $(VERILOGDIR)/$(TOP_MODULE).v> $(VERILOGDIR)/tmp.v
	cat ./elfmem.v $(VERILOGDIR)/tmp.v > $(VERILOGDIR)/$(TOP_MODULE)_ed.v
	verilator $(VERILATOR_FLAGS) --threads-dpi all --cc $(TOP_MODULE)_ed.v --exe elfmem.cpp sim_main.cpp -y $(VERILOGDIR) \
		-y $(BSC_VDIR) $(CUST_VSTR) -y common_verilog 
	@ln -f -s ../sim_main.cpp obj_dir/sim_main.cpp
	@ln -f -s ../elfmem.cpp obj_dir/elfmem.cpp
	@ln -f -s ../sim_main.h obj_dir/sim_main.h
	make $(VERILATOR_SPEED) VM_PARALLEL_BUILDS=1 -j4 -C obj_dir -f V$(TOP_MODULE)_ed.mk
	@cp obj_dir/V$(TOP_MODULE)_ed $(BSVOUTDIR)/out
```
