############ DO NOT CHANGE THESE ################
INCDIR:= ./bluespec_src:./test/:./common_bsv/
CUST_VDIR = ./verilog_src
TOP_MODULE:=mktest
IN:=0
OUT:=0
SIG:=53
EXP:=11
XLEN:=64
norec:=
custom_flags:= -D dpfpu 

FPGA_PART=xc7a100tcsg324-1
FPGA_BOARD=digilentinc.com:arty-a7-100:part0:1.0
FPGA_BOARD_ALIAS=arty100t
JTAG_TYPE=BSCAN2E
JOBS=10

############# User changes to be done below #################
TOP_DIR:=test
TOP_FILE:=testbench.bsv


