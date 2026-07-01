### Makefile for the devices

include Makefile.inc

BUILD:=./build/
BSVBUILDDIR:=$(BUILD)/hw/intermediate/
VERILOGDIR:=$(BUILD)/hw/verilog/
BSVOUTDIR:=./bin/
synth?=NOSYNTH
define_macros:= -D simulate -D ASSERT -D causesize=6 -D in=$(IN) -D out=$(OUT) -D sigwidth=$(SIG) -D expwidth=$(EXP) -D xlen=$(XLEN) -D FORDERING_DEPTH=20 -D SPFMA_STAGE_0=Pre -D SPFMA_STAGE_1=Mac -D SPFMA_STAGE_2=Post -D SPFMA_STAGE_3=Round -D SPFMA_STAGE_0_IN=0 -D SPFMA_STAGE_1_IN=0 -D SPFMA_STAGE_2_IN=0 -D SPFMA_STAGE_3_IN=0 -D SPFMA_STAGE_0_OUT=1 -D SPFMA_STAGE_1_OUT=1 -D SPFMA_STAGE_2_OUT=1 -D SPFMA_STAGE_3_OUT=1 -D DPFMA_STAGE_0_OUT=2 -D DPFMA_STAGE_1_OUT=2 -D DPFMA_STAGE_2_OUT=2 -D DPFMA_STAGE_3_OUT=2 -D DPFMA_STAGE_0_IN=0 -D DPFMA_STAGE_1_IN=0 -D DPFMA_STAGE_2_IN=0 -D DPFMA_STAGE_3_IN=0 -D DPFMA_STAGE_0=Pre -D DPFMA_STAGE_1=Mac -D DPFMA_STAGE_2=Post -D DPFMA_STAGE_3=Round -D fbox_noinline $(custom_flags) $(norec)
FPGA_BUILD_DIR:=build/hw/fpga
COCO_TESTS:=

Vivado_loc=$(shell which vivado || which vivado_lab)

# ---------- bluespec related settings -----------------------
BSVINCDIR:= ./:%/Libraries:$(INCDIR)
BSC_DIR:=$(shell which bsc)
BSC_VDIR:=$(subst bin/bsc,bin/,${BSC_DIR})../lib/Verilog
CUST_VSTR:=$(foreach var,$(CUST_VDIR),-y $(var) )
BSCCMD:=bsc -u -verilog -elab -vdir $(VERILOGDIR) -bdir $(BSVBUILDDIR) -info-dir $(BSVBUILDDIR) \
	+RTS -K40000M -RTS -check-assert  -keep-fires -opt-undetermined-vals -remove-false-rules \
	-remove-empty-rules -remove-starved-rules -remove-dollar -unspecified-to X -show-schedule \
	-steps-warn-interval 500000 -show-module-use $(define_macros)
# -------------------------------------------------------------

# ---------- verilator related settings -----------------------
VERILATOR_FLAGS:= -O3 -LDFLAGS "-static" --x-assign fast  --x-initial fast --noassert \
	sim_main.cpp --bbox-sys -Wno-STMTDLY  -Wno-UNOPTFLAT -Wno-WIDTH -Wno-lint -Wno-COMBDLY \
	-Wno-INITIALDLY  --autoflush   --threads 1 -DBSV_RESET_FIFO_HEAD  -DBSV_RESET_FIFO_ARRAY \
	--output-split 20000  --output-split-ctrace 10000
VERILATOR_SPEED:=OPT_SLOW="-O3" OPT_FAST="-O3"
# -------------------------------------------------------------

default: generate_verilog link_verilator simulate

.PHONY: link_verilator
link_verilator: ## Generate simulation executable using Verilator
	@echo $(CUST_VDIR)
	@echo $(CUST_CVSTR)
	@echo "Linking $(TOP_MODULE) using verilator"
	@mkdir -p $(BSVOUTDIR) obj_dir
	@echo "#define TOPMODULE V$(TOP_MODULE)" > sim_main.h
	@echo '#include "V$(TOP_MODULE).h"' >> sim_main.h
	verilator $(VERILATOR_FLAGS) +1364-2001ext+.v --cc $(TOP_MODULE).v \
		-y $(VERILOGDIR) \
		-y $(BSC_VDIR) $(CUST_VSTR) -y common_verilog --exe
	@ln -f -s ../test_soc/sim_main.cpp obj_dir/sim_main.cpp
	@ln -f -s ../sim_main.h obj_dir/sim_main.h
	make $(VERILATOR_SPEED) VM_PARALLEL_BUILDS=1 -j4 -C obj_dir -f V$(TOP_MODULE).mk
	@cp obj_dir/V$(TOP_MODULE) $(BSVOUTDIR)/out

.PHONY: generate_verilog 
generate_verilog:
	@echo Compiling $(TOP_MODULE) in verilog ...
	@mkdir -p $(BSVBUILDDIR); 
	@mkdir -p $(VERILOGDIR); 
	$(BSCCMD) -p $(BSVINCDIR) -g $(TOP_MODULE) $(TOP_DIR)/$(TOP_FILE)  || (echo "BSC COMPILE ERROR"; exit 1)
	@cp ${BSC_VDIR}/../Verilog.Vivado/RegFile.v ${VERILOGDIR}
	@cp ${BSC_VDIR}/FIFO2.v ${VERILOGDIR}
	@cp ${BSC_VDIR}/FIFOL1.v ${VERILOGDIR}
	@cp ${BSC_VDIR}/RevertReg.v ${VERILOGDIR}
	@cp ${BSC_VDIR}/../Verilog.Vivado/SizedFIFO.v ${VERILOGDIR}
	@cp ./verilog_src/* ${VERILOGDIR}

.PHONY: test
test: generate_verilog
	# @ testfloat_gen -rnear_maxMag f64_mulAdd > ./test/fma64.txt
	@ testfloat_gen -rnear_maxMag ui64 > ./test/cvtui64d.txt
	@ cd test/; make TESTCASE=$(COCO_TESTS) TOPLEVEL=$(TOP_MODULE)

.PHONY: fpga_build
fpga_build: generate_verilog
	vivado -nojournal -nolog -mode tcl -notrace -source tcl/create_project.tcl -tclargs $(FPGA_BOARD_ALIAS) $(FPGA_BOARD) $(FPGA_PART) $(JTAG_TYPE) $(VERILOGDIR) $(TOP_MODULE) \
	|| (echo "Could not create core project"; exit 1)
	vivado -nojournal -log fpgabuild.log -notrace -mode tcl -source tcl/run.tcl \
		-tclargs $(JOBS) || (echo "ERROR: While running synthesis")

.PHONY: save_artifacts
save_artifacts: fpga_build
	@ mkdir -p artifacts/${TOP_MODULE}
	@ cp build/fbox/syn_*.txt artifacts/${TOP_MODULE}

.PHONY: genstructs
genstructs: generate_verilog
	./tcl/genStructInfo.tcl > $(BUILD)/structinfo.txt
	python python-utils/cocotb_utils/write_structs.py

.PHONY: simulate
simulate:
	@echo Simulating $(TOP_MODULE)
	@./bin/out 
	@echo Simulation Done

.PHONY: clean
clean:
	rm -rf $(BUILD) $(BSVOUTDIR) *.jou *.log obj_dir sim_main.h
	rm -rf test/sim_build
	rm -rf test/*.vcd 
	rm -rf test/*.xml
