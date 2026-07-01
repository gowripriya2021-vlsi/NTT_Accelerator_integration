TOPLEVEL_LANG ?= verilog

TOPLEVEL := mktestbench
VERILOG_SOURCES = $(shell pwd)/../build/hw/verilog/$(TOPLEVEL).v

SIM ?= verilator
include ../Makefile.inc
BSC_DIR:=$(shell which bsc)
BSC_VDIR:=$(subst bin/bsc,bin/,${BSC_DIR})../lib/Verilog
CUST_VSTR:=$(foreach var,$(CUST_VDIR),-y $(var) )

COMPILE_ARGS ?= -O3 --x-assign fast --x-initial fast --noassert \
        --bbox-sys -Wno-STMTDLY -Wno-UNOPTFLAT -Wno-WIDTH -Wno-lint \
        -Wno-COMBDLY -Wno-TIMESCALEMOD -Wno-INITIALDLY --autoflush \
        -y $(shell pwd)/../build/hw/verilog/ \
		-y $(BSC_VDIR) $(CUST_VSTR) -y ../common_verilog --output-split 20000  --output-split-ctrace 10000 \
        -DBSV_RESET_FIFO_HEAD -DBSV_RESET_FIFO_ARRAY --trace

COCOTB_REDUCED_LOG_FMT ?= True

PLUSARGS := +mtestbench +l1 +l2 +l0 +mfbox

MODULE = testbench

include $(shell cocotb-config --makefiles)/Makefile.inc
include $(shell cocotb-config --makefiles)/Makefile.sim
