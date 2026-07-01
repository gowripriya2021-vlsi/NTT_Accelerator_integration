### Makefile for the devices

include $(CONFIG)

BSVBUILDDIR:=./build/
VERILOGDIR:=./verilog/
BSVINCDIR:= .:%/Libraries:$(DIR)
BSVOUTDIR:=./bin
BSC_DIR:=$(shell which bsc)
BSC_VDIR:=$(subst bin/bsc,bin/,${BSC_DIR})../lib/Verilog

define_macros += -D Addr_space=25
ifeq ($(DTLB_NOINLINE), enable)
	override define_macros += -D dtlb_noinline
endif
ifeq ($(ECC_TEST), enable)
	override define_macros += -D ecc_test
endif
ifeq ($(ECC), enable)
	override define_macros += -D dcache_ecc
endif
ifeq ($(SVNAPOT), enable)
  override define_macros += -D svnapot
endif
ifeq ($(HYPERVISOR), enable)
  override define_macros += -D hypervisor
endif
ifeq ($(DUMMY), enable)
  override define_macros += -D dummy
endif
ifeq ($(ATOMIC), enable)
  override define_macros += -D atomic=True
endif
ifeq ($(DCACHE), enable)
  override define_macros += -D dcache=True
endif
ifeq ($(PORT), dual)
  override define_macros += -D dcache_dualport
endif

ifneq ($(SUPERVISOR),  none)
  override define_macros += -D supervisor=True -D $(SUPERVISOR) -D perfmonitors
endif
ifeq ($(COVERAGE), none)
else ifeq ($(COVERAGE),all)
  coverage := --coverage
else
  coverage := --coverage-$(COVERAGE)
endif

ifneq ($(PMPSIZE) , 0)
  override define_macros += -D pmp -D pmpsize=$(PMPSIZE)
endif

ifeq ($(TRACE), enable)
  trace := --trace
endif

override define_macros += -D ASSERT=True -D dwords=$(DWORDS) -D dblocks=$(DBLOCKS) -D dways=$(DWAYS) \
								-D dsets=$(DSETS) -D drepl=$(DREPL) -D dcachereset=$(DRESET) -D dsbsize=$(DSBSIZE)\
								-D dfbsize=$(DFBSIZE)\
								-D $(SA_OR_FA)\
								-D xlen=$(XLEN)\
								-D ppnsize=$(PPNSIZE)\
								-D page_offset=$(PAGE_OFFSET)\
								-D max_varpages=$(MAX_VARPAGES) -D subvpn=$(SUBVPN) -D lastppnsize=$(LASTPPNSIZE)\
								-D maxvaddr=$(MAXVADDR) -D vpnsize=$(VPNSIZE) -D satp_mode_size=$(SATP_MODE_SIZE)\
								-D desize=$(DESIZE) -D dtbanks=$(DTBANKS) \
								-D paddr=$(PADDR) -D vaddr=$(XLEN) -D RV$(XLEN)=True -D asidwidth=$(ASIDWIDTH) -D vmidwidth=$(VMIDWIDTH) \
								-D simulate=True -D dtlbsize=$(DTLBSIZE) -D itlbsize=$(ITLBSIZE) -D causesize=6 \
								-D dbuswidth=$(DBUSWIDTH) -D pmp_grainbits=$(GRAINBITS)	-D dcache_onehot=$(ONE_HOT)\
								-D dtlb_sets_4kb=$(DTLB_SETS_4KB) -D dtlb_sets_64kb=$(DTLB_SETS_64KB) -D dtlb_sets_4mb=$(DTLB_SETS_4MB) \
								-D dtlb_sets_2mb=$(DTLB_SETS_2MB) -D dtlb_sets_1gb=$(DTLB_SETS_1GB)\
								-D dtlb_sets_512gb=$(DTLB_SETS_512GB) -D dtlb_sets_256tb=$(DTLB_SETS_256TB)\
								-D dtlb_ways_4kb=$(DTLB_WAYS_4KB) -D dtlb_ways_64kb=$(DTLB_WAYS_64KB) -D dtlb_ways_4mb=$(DTLB_WAYS_4MB) \
								-D dtlb_ways_2mb=$(DTLB_WAYS_2MB) -D dtlb_ways_1gb=$(DTLB_WAYS_1GB)\
								-D dtlb_ways_512gb=$(DTLB_WAYS_512GB) -D dtlb_ways_256tb=$(DTLB_WAYS_256TB)\
								-D dtlb_rep_alg_4kb=$(DTLB_REP_ALG_4KB) -D dtlb_rep_alg_64kb=$(DTLB_REP_ALG_64KB) -D dtlb_rep_alg_4mb=$(DTLB_REP_ALG_4MB) \
								-D dtlb_rep_alg_2mb=$(DTLB_REP_ALG_2MB) -D dtlb_rep_alg_1gb=$(DTLB_REP_ALG_1GB)\
								-D dtlb_rep_alg_512gb=$(DTLB_REP_ALG_512GB) -D dtlb_rep_alg_256tb=$(DTLB_REP_ALG_256TB)\
								-D itlb_sets_4kb=$(ITLB_SETS_4KB) -D itlb_sets_64kb=$(ITLB_SETS_64KB) -D itlb_sets_4mb=$(ITLB_SETS_4MB) \
								-D itlb_sets_2mb=$(ITLB_SETS_2MB) -D itlb_sets_1gb=$(ITLB_SETS_1GB)\
								-D itlb_sets_512gb=$(ITLB_SETS_512GB) -D itlb_sets_256tb=$(ITLB_SETS_256TB)\
								-D itlb_ways_4kb=$(ITLB_WAYS_4KB) -D itlb_ways_64kb=$(ITLB_WAYS_64KB) -D itlb_ways_4mb=$(ITLB_WAYS_4MB) \
								-D itlb_ways_2mb=$(ITLB_WAYS_2MB) -D itlb_ways_1gb=$(ITLB_WAYS_1GB)\
								-D itlb_ways_512gb=$(ITLB_WAYS_512GB) -D itlb_ways_256tb=$(ITLB_WAYS_256TB)\
								-D itlb_rep_alg_4kb=$(ITLB_REP_ALG_4KB) -D itlb_rep_alg_64kb=$(ITLB_REP_ALG_64KB) -D itlb_rep_alg_4mb=$(ITLB_REP_ALG_4MB) \
								-D itlb_rep_alg_2mb=$(ITLB_REP_ALG_2MB) -D itlb_rep_alg_1gb=$(ITLB_REP_ALG_1GB)\
								-D itlb_rep_alg_512gb=$(ITLB_REP_ALG_512GB) -D itlb_rep_alg_256tb=$(ITLB_REP_ALG_256TB)	
								

verilate_fast := OPT_SLOW="-O3" OPT_FAST="-O3"
VERILATOR_FLAGS:= -O3 -LDFLAGS "-static" --x-assign fast  --x-initial fast --noassert sim_main.cpp --bbox-sys -Wno-STMTDLY  -Wno-UNOPTFLAT -Wno-WIDTH -Wno-lint -Wno-COMBDLY -Wno-INITIALDLY  --autoflush   --threads 1 -DBSV_RESET_FIFO_HEAD  -DBSV_RESET_FIFO_ARRAY --output-split 20000  --output-split-ctrace 10000

VCS_MACROS = +define+BSV_RESET_FIFO_HEAD=True +define+BSV_RESET_FIFO_ARRAY=True +define+BSV_ASYNC_RESET +define+VERBOSE

define presim_config
	python3 gen_test.py
endef
default: generate_verilog link_verilator simulate

.PHONY: compile
compile:
	@echo Compiling $(TOP_MODULE)....
	@mkdir -p $(BSVBUILDDIR)
	@bsc -u -sim -simdir $(BSVBUILDDIR) -bdir $(BSVBUILDDIR) -info-dir $(BSVBUILDDIR) -keep-fires \
	-suppress-warnings S0015 -check-assert $(define_macros) -p $(BSVINCDIR) -g $(TOP_MODULE)  \
	$(TOP_DIR)/$(TOP_FILE) 
	@echo Compilation finished

.PHONY: link
link:
	@echo Linking $(TOP_MODULE)...
	@mkdir -p bin
	@bsc -e $(TOP_MODULE) -sim -o ./bin/out -simdir $(BSVBUILDDIR) -p .:%/Prelude:%/Libraries:%/Libraries/BlueNoC -keep-fires -bdir $(BSVBUILDDIR) -keep-fires  
	@echo Linking finished

.PHONY: generate_verilog 
generate_verilog:
	@echo Compiling $(TOP_MODULE) in verilog ...
	@mkdir -p $(BSVBUILDDIR); 
	@mkdir -p $(VERILOGDIR); 
	@echo "old_define_macros = $(define_macros)" > vars
	bsc -u -verilog -elab -vdir $(VERILOGDIR) -bdir $(BSVBUILDDIR) -info-dir $(BSVBUILDDIR) \
		+RTS -K40000M -RTS -check-assert  -keep-fires -opt-undetermined-vals -remove-false-rules \
		-remove-empty-rules -remove-starved-rules -remove-dollar -unspecified-to X -show-schedule \
		-show-module-use $(define_macros) -D verilog=True $(BSVCOMPILEOPTS) \
		-p $(BSVINCDIR) -g $(TOP_MODULE) $(TOP_DIR)/$(TOP_FILE)  || (echo "BSC COMPILE ERROR"; exit 1) 
	@cp bsvwrappers/common_lib/*.v $(VERILOGDIR)
	@cp ${BSC_VDIR}/../Verilog.Vivado/RegFile.v $(VERILOGDIR)  
	@cp ${BSC_VDIR}/FIFO2.v $(VERILOGDIR)
	@cp ${BSC_VDIR}/FIFO1.v $(VERILOGDIR)
	@cp ${BSC_VDIR}/FIFO10.v $(VERILOGDIR)
	@cp ${BSC_VDIR}/RevertReg.v $(VERILOGDIR)
	@cp ${BSC_VDIR}/FIFO20.v $(VERILOGDIR)
	@cp ${BSC_VDIR}/FIFOL1.v $(VERILOGDIR)
	@cp ${BSC_VDIR}/SyncFIFO.v $(VERILOGDIR)
	@cp ${BSC_VDIR}/Counter.v $(VERILOGDIR)
	@cp ${BSC_VDIR}/SizedFIFO.v $(VERILOGDIR)
	@cp ${BSC_VDIR}/RegFileLoad.v $(VERILOGDIR)

.PHONY: link_vcs
link_vcs: ## Generate simulation executable using Synopsys VCS
	@rm -rf $(BSVOUTDIR)
	@mkdir -p $(BSVOUTDIR)
	vcs -gui -LDFLAGS -Wl,--no-as-needed -l vcs_compile.log -sverilog +vpi +v2k -lca +define+TOP=$(TOP_MODULE) $(VCS_MACROS) \
	+define+BSV_TIMESCALE=1ns/1ps +cli+4 +libext+.v +notimingcheck \
	-y $(VERILOGDIR)/ -y bsvwrappers/common_lib/ \
	${BLUESPECDIR}/Verilog/main.v -o out
	@mv csrc out* $(BSVOUTDIR)

.PHONY: link_verilator
link_verilator: 
	@echo "Linking $(TOP_MODULE) using verilator"
	@mkdir -p $(BSVOUTDIR) obj_dir
	@echo "#define TOPMODULE V$(TOP_MODULE)" > sim_main.h
	@echo '#include "V$(TOP_MODULE).h"' >> sim_main.h
	verilator $(VERILATOR_FLAGS) --cc $(TOP_MODULE).v -y $(VERILOGDIR) --exe
	@ln -f -s ../sim_main.cpp obj_dir/sim_main.cpp
	@ln -f -s ../sim_main.h obj_dir/sim_main.h
	make $(verilate_fast) VM_PARALLEL_BUILDS=1 -j8 -C obj_dir -f V$(TOP_MODULE).mk
	@cp obj_dir/V$(TOP_MODULE) bin/out

.PHONY: simulate
simulate:
	@echo Simulation...
	$(call presim_config)
	@exec ./$(BSVOUTDIR)/out
	@echo Simulation finished

.PHONY: clean
clean:
	rm -rf build bin *.jou *.log test.mem  log verilog fpga obj_dir sim_main.h vars data.mem

