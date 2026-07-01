include Makefile.inc

linesize=$$(($(xlen)/8))
target ?= CUSTOM
ITERATIONS ?= 5000
RISCV_PREFIX ?= riscv$(xlen)-unknown-elf-
RISCV_GCC ?= $(RISCV_PREFIX)gcc
RISCV_LINK_OPTS ?= -static -nostartfiles -lgcc -T ./common/link.ld
RISCV_HEX = elf2hex $(linesize) $$((4194304*64/$(xlen)))
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump -D
OUTDIR ?= output
FLAGS_STR = -mcmodel=medany -D$(target) -DPERFORMANCE_RUN=1 -DMAIN_HAS_NOARGC=1 -DHAS_STDIO \
					  -DHAS_PRINTF -DHAS_TIME_H -DUSE_CLOCK -DHAS_FLOAT=0 -DITERATIONS=$(ITERATIONS) \
						-O3 -fno-common -funroll-loops -finline-functions -fselective-scheduling \
						-falign-functions=16 -falign-jumps=4 -falign-loops=4 -finline-limit=1000 \
					 	-nostartfiles -nostdlib -ffast-math -fno-builtin-printf -march=$(march)\
						-mexplicit-relocs -ffreestanding -fno-builtin -mtune=rocket

FLAGS = "$(FLAGS_STR)"


.PHONY: dhrystone
dhrystone: 
	@echo "Compiling Dhrystone"
	@mkdir -p output/
	$(RISCV_GCC) -I./common -D$(target) -DCONFIG_RISCV64=True -mcmodel=medany -static -std=gnu99\
		-O2 -fno-inline -ffast-math -fno-common -fno-builtin-printf -march=$(march) -mabi=$(mabi) -w -static -mtune=rocket\
		-nostartfiles -lgcc -c common/crt.S -o output/crt.o -fno-tree-loop-distribute-patterns
	$(RISCV_GCC) -I./common -D$(target) -DCONFIG_RISCV64=True -mcmodel=medany -static -std=gnu99\
		-O2 -fno-inline -ffast-math -fno-common -fno-builtin-printf -march=$(march) -mabi=$(mabi) -w -static -mtune=rocket\
		-nostartfiles -lgcc -c common/syscalls.c -o output/syscalls.o -fno-tree-loop-distribute-patterns
	$(RISCV_GCC) -I./common -I./dhrystone -DCONFIG_RISCV64=True \
				-DITERATIONS=$(ITERATIONS) -D$(target)=True -mcmodel=medany -static -std=gnu99 -O2 -fno-inline -ffast-math \
				-fno-common -fno-builtin-printf -march=$(march) -mabi=$(mabi) -mtune=rocket\
				-w -static -nostartfiles -lgcc -T ./common/link.ld -o $(OUTDIR)/dhry.riscv \
				./dhrystone/dhry_1.c ./dhrystone/dhry_2.c ./output/syscalls.o ./output/crt.o -fno-tree-loop-distribute-patterns
	$(RISCV_OBJDUMP) $(OUTDIR)/dhry.riscv > $(OUTDIR)/dhry.dump
	$(RISCV_HEX) $(OUTDIR)/dhry.riscv 2147483648 > $(OUTDIR)/code.mem


.PHONY: hello
hello:
	@echo "Compiling Hello"
	@mkdir -p output/
	$(RISCV_GCC) -I./common -I./hello -DCONFIG_RISCV64=True \
				-D$(target)=True -mcmodel=medany -static -std=gnu99 -O2 -fno-inline -ffast-math \
				-fno-common -fno-builtin-printf -march=$(march) -mabi=$(mabi) -w -static \
				-nostartfiles -lgcc -T ./common/link.ld -o $(OUTDIR)/hello.riscv ./hello/hello.c \
				./common/syscalls.c ./common/crt.S
	@$(RISCV_OBJDUMP) $(OUTDIR)/hello.riscv > $(OUTDIR)/hello.dump
	@$(RISCV_HEX) $(OUTDIR)/hello.riscv 2147483648 > $(OUTDIR)/code.mem

.PHONY: mult	
mult:
	@echo "Compiling Mult"
	@mkdir -p output/
	$(RISCV_GCC) -I./common -I./ntt -DCONFIG_RISCV64=True \
				-D$(target)=True -mcmodel=medany -static -std=gnu99 -O2 -fno-inline -ffast-math \
				-fno-common -fno-builtin-printf -march=$(march) -mabi=$(mabi) -w -static \
				-nostartfiles -lgcc -T ./common/link.ld -o $(OUTDIR)/mult.riscv ./mult/mul_test.c \
				./common/syscalls.c ./common/crt.S
	@$(RISCV_OBJDUMP) $(OUTDIR)/mult.riscv > $(OUTDIR)/mult.dump
	@$(RISCV_HEX) $(OUTDIR)/mult.riscv 2147483648 > $(OUTDIR)/code.mem
.PHONY: ntt	
ntt:
	@echo "Compiling ntt"
	@mkdir -p output/
	$(RISCV_GCC) -I./common -I./ntt -DCONFIG_RISCV64=True \
				-D$(target)=True -mcmodel=medany -static -std=gnu99 -O2 -fno-inline -ffast-math \
				-fno-common -fno-builtin-printf -march=$(march) -mabi=$(mabi) -w -static \
				-nostartfiles -lgcc -T ./common/link.ld -o $(OUTDIR)/ntt.riscv ./ntt/ntt_test.c \
				./common/syscalls.c ./common/crt.S
	@$(RISCV_OBJDUMP) $(OUTDIR)/ntt.riscv > $(OUTDIR)/ntt.dump
	@$(RISCV_HEX) $(OUTDIR)/ntt.riscv 2147483648 > $(OUTDIR)/code.mem	


.PHONY: kyber	
kyber:
	@echo "Compiling kyber"
	@mkdir -p output/
	$(RISCV_GCC) -I./common -I./ntt -I./kyber/ref -DCONFIG_RISCV64=True \-DCPU_HZ=50000000 \
				-D$(target)=True -mcmodel=medany -static -std=gnu99 -O2 -fno-inline -ffast-math \
				-fno-common -fno-builtin-printf -march=$(march) -mabi=$(mabi) -w -static \
				-nostartfiles -lgcc -T ./common/link.ld -o $(OUTDIR)/kyber.riscv \
				./kyber/ref/test/test_kyber.c \
				./kyber/ref/ntt_kyber_hw.c \
				./kyber/ref/kem.c \
				./kyber/ref/indcpa.c \
				./kyber/ref/polyvec.c \
				./kyber/ref/poly.c \
				./kyber/ref/ntt.c \
				./kyber/ref/cbd.c \
				./kyber/ref/reduce.c \
				./kyber/ref/verify.c \
				./kyber/ref/symmetric-shake.c \
				./kyber/ref/fips202.c \
				./common/randombytes.c \
				./common/syscalls.c ./common/crt.S
	@$(RISCV_OBJDUMP) $(OUTDIR)/kyber.riscv > $(OUTDIR)/kyber.dump
	@$(RISCV_HEX) $(OUTDIR)/kyber.riscv 2147483648 > $(OUTDIR)/code.mem


# =============================================================================
# kyber-sw  —  pure-software Kyber (no HW accelerator, for correctness baseline)
#
# Useful for:
#   • Verifying Kyber correctness independently of the HW accelerator
#   • Generating golden reference output to compare against kyber (HW) run
#
# The only difference from the 'kyber' target is that -DCUSTOM=True is
# replaced by nothing, so poly_ntt calls the software ntt() function.
# =============================================================================
.PHONY: kyber_sw
kyber_sw:
	@echo "──────────────────────────────────────────────────────"
	@echo "Compiling Kyber KEM (software NTT, no HW) for Chromite RV$(xlen)"
	@echo "──────────────────────────────────────────────────────"
	@mkdir -p $(OUTDIR)/
	$(RISCV_GCC) \
		-I./common \
		-I./kyber_sw/ref \
		-I./kyber_sw/ref/test \
		-UKYBER_NAMESPACE \
		'-DKYBER_NAMESPACE(s)=s' \
		-UKYBER_NAMESPACE \
		'-DFIPS202_NAMESPACE(s)=s' \
		-DCONFIG_RISCV64=True \
		-DUART_OUT=True \
		-mcmodel=medany \
		-static \
		-std=gnu99 \
		-O2 \
		-ffast-math \
		-fno-common \
		-fno-builtin-printf \
		-march=$(march) \
		-mabi=$(mabi) \
		-w \
		-static \
		-nostartfiles \
		-lgcc \
		-fno-tree-loop-distribute-patterns \
		-T ./common/link.ld \
		-o $(OUTDIR)/kyber_sw.riscv \
		./kyber_sw/ref/test/test_kyber.c \
		./kyber_sw/ref/kem.c \
		./kyber_sw/ref/indcpa.c \
		./kyber_sw/ref/polyvec.c \
		./kyber_sw/ref/poly.c \
		./kyber_sw/ref/ntt.c \
		./kyber_sw/ref/cbd.c \
		./kyber_sw/ref/reduce.c \
		./kyber_sw/ref/verify.c \
		./kyber_sw/ref/symmetric-shake.c \
		./kyber_sw/ref/fips202.c \
		./common/randombytes.c \
		./common/syscalls.c \
		./common/crt.S
	@echo "✓ ELF  → $(OUTDIR)/kyber_sw.riscv"
	@$(RISCV_OBJDUMP) $(OUTDIR)/kyber_sw.riscv > $(OUTDIR)/kyber_sw.dump
	@echo "✓ Dump → $(OUTDIR)/kyber_sw.dump"
	@$(RISCV_HEX) $(OUTDIR)/kyber_sw.riscv 2147483648 > $(OUTDIR)/code.mem
	@echo "✓ Hex  → $(OUTDIR)/code.mem"
	@echo "──────────────────────────────────────────────────────"



.PHONY: coremarks
coremarks:
	@echo "Compiling Coremarks"
	@mkdir -p output/
	@$(RISCV_GCC) -I./common -D$(target) -DCONFIG_RISCV64=True -mcmodel=medany -static -std=gnu99\
		-O2 -fno-inline -ffast-math -fno-common -fno-builtin-printf -march=$(march) -mabi=$(mabi) -w -static -mtune=rocket\
		-nostartfiles -lgcc -c common/crt.S -o output/crt.o
	@$(RISCV_GCC) -I./common -D$(target) -DCONFIG_RISCV64=True -mcmodel=medany -static -std=gnu99\
		-O2 -fno-inline -ffast-math -fno-common -fno-builtin-printf -march=$(march) -mabi=$(mabi) -w -static -mtune=rocket\
		-nostartfiles -lgcc -c common/syscalls.c -o output/syscalls.o
	$(RISCV_GCC) -I./common -I./coremarks $(FLAGS_STR) $(RISCV_LINK_OPTS) -o $(OUTDIR)/coremarks.riscv \
		./coremarks/core_util.c ./coremarks/ee_printf.c ./coremarks/core_state.c \
		-DFLAGSTR=\"$(FLAGS)\" \
		./coremarks/core_list_join.c ./coremarks/core_portme.c ./coremarks/core_main.c \
		./coremarks/core_matrix.c ./output/crt.o ./output/syscalls.o
	@$(RISCV_OBJDUMP) $(OUTDIR)/coremarks.riscv > $(OUTDIR)/coremarks.dump
	@$(RISCV_HEX) $(OUTDIR)/coremarks.riscv 2147483648 > $(OUTDIR)/code.mem


.PHONY: clean
clean:
	rm -rf $(OUTDIR)

.PHONY: kyber-kat
kyber-kat:
	@echo "Compiling Kyber NIST KAT (1 iteration)"
	@mkdir -p $(OUTDIR)/
	$(RISCV_GCC) -I./common -I./kyber/ref -I./kyber/ref/nistkat \
		-DCONFIG_RISCV64=True -DCUSTOM=True \
		-mcmodel=medany -static -std=gnu99 -O2 -fno-inline \
		-fno-common -fno-builtin-printf \
		-march=$(march) -mabi=$(mabi) -w -static \
		-nostartfiles -lgcc -T ./common/link.ld \
		-o $(OUTDIR)/kyber_kat.riscv \
		./kyber/ref/nistkat/PQCgenKAT_kem_baremetal.c \
		./kyber/ref/nistkat/rng_baremetal.c \
		./kyber/ref/ntt_kyber_hw.c \
		./kyber/ref/kem.c \
		./kyber/ref/indcpa.c \
		./kyber/ref/polyvec.c \
		./kyber/ref/poly.c \
		./kyber/ref/ntt.c \
		./kyber/ref/cbd.c \
		./kyber/ref/reduce.c \
		./kyber/ref/verify.c \
		./kyber/ref/symmetric-shake.c \
		./kyber/ref/fips202.c \
		./common/syscalls.c ./common/crt.S
	@$(RISCV_OBJDUMP) $(OUTDIR)/kyber_kat.riscv > $(OUTDIR)/kyber_kat.dump
	@$(RISCV_HEX) $(OUTDIR)/kyber_kat.riscv 2147483648 > $(OUTDIR)/code.mem
