xlen=64
linesize=$(xlen)/4
RISCV_PREFIX ?= riscv$(xlen)-unknown-elf-
RISCV_GCC ?= $(RISCV_PREFIX)gcc
RISCV_LINK_OPTS ?= -static -nostartfiles -lgcc -T ./link.ld
RISCV_HEX = elf2hex $(linesize) 128 debugrom.elf 0
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump -D
RISCV_GCC_ARGS ?= -mcmodel=medany -static -std=gnu99 -O2 -ffast-math -fno-common \
									-fno-builtin-printf -march=rv64i -w -static	-nostartfiles -lgcc \
									-c debugrom.S -o debugrom.elf
        
default: build

.PHONY: build         
build:
	$(RISCV_GCC) $(RISCV_GCC_ARGS) $(RISCV_LINK_OPTS)
	$(RISCV_OBJDUMP) debugrom.elf > objdump
	$(RISCV_HEX)
