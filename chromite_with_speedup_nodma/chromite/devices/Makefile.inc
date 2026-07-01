############ DO NOT CHANGE THESE ################
INCDIR:=./common_bsv:./fabrics/axi4_lite/:./fabrics/apb:./fabrics/axi4:./bsvwrappers/common_lib:./ram1rw/:./ram2rw:./aclint:./clint:./gpio:./plic:./uart:./rom:./riscv_debug/:./bootconfig/:./uart16550/:./pwm:./spi:./qspi:./prot_ocm:./riscvdebug100/
TOP_MODULE:=mkinst_debugapb

############# User changes to be done below #################
TOP_DIR:=riscvdebug100
TOP_FILE:=debug_instance.bsv
#TOP_FILE:=qspi_instance.bsv

