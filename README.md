# NTT Hardware Accelerator for Kyber-768 (RISC-V SoC)

Hardware/software co-design of a Number Theoretic Transform (NTT) accelerator
for Kyber-768 post-quantum cryptography, integrated into a Chromite RISC-V
SoC via AXI4. Developed as part of M.Tech VLSI Design research at NITK
Surathkal, in collaboration with CUSAT's CArS Lab and InCore Semiconductors.

## Overview

Kyber-768 key generation, encapsulation, and decapsulation rely heavily on
the NTT (~90 calls per KEM cycle). This project implements a custom NTT
accelerator in BSV/Verilog, interfaced to a RISC-V core over AXI4, with the
goal of offloading NTT compute from software while minimizing MMIO/DMA
overhead.

**Core contributions:**
- Correct **negacyclic NTT** (mod x²⁵⁶+1, 7-stage butterfly) with
  bit-reversed twiddle factor ordering — replacing an initial cyclic
  (8-stage) implementation that caused Kyber key mismatches (KA ≠ KB).
- Diagnosis of **AXI MMIO overhead** as the dominant bottleneck (~72% of
  NTT call cycles vs. ~7% hardware compute), driven by 512 single-beat
  transactions per call.
- Progressive optimization: single-beat MMIO → burst coalescing
  (16 bursts × 16 beats) → full **DMA-capable accelerator**
  (`NTTAXI4.bsv`) with a three-phase FSM (`LOADING → RUNNING → DONE`),
  reducing CPU-side I/O to 3 MMIO writes + polling.
- Per-call cycle/instruction profiling via RISC-V `rdcycle`/`rdinstret`
  CSRs, breaking down AXI-write, compute, AXI-read, pack, and unpack
  phases.
- Barrett reduction (k=24, M=5039) to eliminate synthesized dividers.
- Fixed a linker script bug (missing `.rodata`) that placed the stack
  pointer inside the NTT peripheral's AXI address window, causing AXI
  deadlocks and spurious START triggers.

## Repository Structure

```
.
├── hw/
│   ├── NTTAXI4.bsv              # AXI4 DMA-capable NTT accelerator (top)
│   ├── NTTWrapper.bsv           # BSV wrapper / register interface
│   ├── ntt_iterative_optimized.v# Iterative negacyclic NTT butterfly (Verilog)
│   └── Soc.bsv                  # SoC integration
├── sw/
│   ├── ntt_kyber_hw.c            # Software driver for the HW accelerator
│   └── test_kyber.c              # KEM test harness + cycle profiling
├── docs/
│   └── presentation/             # LaTeX Beamer slides (NITK Madrid theme)
├── sim/                           # VCS/Verilator simulation scripts & logs
├── synth/                         # Design Compiler (SCL 180nm) scripts, QOR
└── README.md
```

Adjust this tree to match your actual layout when you add files — this is a
suggested structure based on the project's components.

## Architecture

```
RISC-V Core (Chromite SoC)
        │  AXI4
        ▼
 ┌─────────────────┐
 │   NTTAXI4.bsv    │  3-phase FSM: LOADING → RUNNING → DONE
 │  ┌────────────┐  │
 │  │ NTTWrapper │  │  CTRL register: BUSY (bit 2), DONE (bit 3)
 │  └─────┬──────┘  │
 │        ▼          │
 │  ntt_iterative_   │  7-stage negacyclic butterfly,
 │  optimized.v      │  bit-reversed twiddle ROM
 └─────────────────┘
```

**Register map (CTRL):**
| Bit | Meaning |
|-----|---------|
| 2   | BUSY    |
| 3   | DONE    |

## Key Technical Fixes

1. **Cyclic → negacyclic NTT.** Original 8-stage cyclic NTT (mod x²⁵⁶−1)
   produced incorrect results for Kyber's ring; corrected to 7-stage
   negacyclic (mod x²⁵⁶+1) with proper bit-reversed twiddle ordering.
2. **AXI DMA offload.** Replaced 512 single-beat AXI transactions with a
   DMA engine that streams coefficients in/out, cutting CPU-side MMIO
   traffic to 3 writes + polling.
3. **FSM deadlock fix.** Resolved a DONE→IDLE transition deadlock in the
   control FSM.
4. **CTRL register alignment.** Fixed bit misassignment between BUSY and
   DONE flags.
5. **Verilator lint fixes.** Resolved `BLKLOOPINIT` / `sv2v_autoblock`
   errors from blocking assignments in loops.
6. **Linker script fix.** Added missing `.rodata` section so the stack
   pointer no longer overlapped the NTT peripheral's AXI address window.

## Build & Run

> Fill in with your actual toolchain commands once files are added —
> placeholders below based on tools used during development.

```bash
# BSV compile (bsc)
bsc -sim -g mkSoc -u Soc.bsv

# Verilator sim
verilator --cc ntt_iterative_optimized.v --exe test_kyber.c

# VCS sim (Synopsys)
vcs -sverilog -f filelist.f -o simv_ntt
./simv_ntt | tee ntt_run.log

# ASIC synthesis (Design Compiler, SCL 180nm SS corner)
dc_shell -f synth/run_dc.tcl
```

## Status

- [x] Correct negacyclic NTT implementation
- [x] AXI4 DMA-capable accelerator with 3-phase FSM
- [x] Per-call profiling (cycle/instruction counts)
- [x] Barrett reduction for modular arithmetic
- [x] DC synthesis (SCL 180nm) — 18.77 ns critical path vs. 20 ns clock;
      hold violations pending `set_fix_hold` incremental compile
- [ ] `mem` array RAM inference fix (`ram_style` attribute) — pending
- [ ] Hardware Keccak-f accelerator (identified as higher-impact than
      further NTT optimization for overall Kyber speedup)

## Related Work

A separate, ongoing simulation effort debugs an NTT benchmark
(`ntt.c`) on the InCore `mk_soc_top` SoC (VCS, Synopsys U-2023.03-SP2-1),
independent of this accelerator's RTL — see `sim/` for logs and notes if
merged into this repo.

## Acknowledgements

- Prof. M. S. Bhat (NITK Surathkal, internal advisor)
- Tripti S. Warrier (CUSAT, external advisor)
- CArS Lab, CUSAT
- InCore Semiconductors Pvt. Ltd.
