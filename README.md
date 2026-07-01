# NTT Hardware Accelerator for Kyber-768 (RISC-V SoC)

Hardware/software co-design of a Number Theoretic Transform (NTT) accelerator
for Kyber post-quantum cryptography, integrated into a Chromite/InCore
RISC-V SoC via AXI4. Developed as part of M.Tech VLSI Design research at
NITK Surathkal, in collaboration with CUSAT's CArS Lab and InCore
Semiconductors.

## Status: verified working ✅

Full KeyGen → Encapsulation → Decapsulation round-trip on real hardware
simulation, shared secret matches on both sides:

```
[MATCH] KA == KB  PASS
```

See [Verified Results](#verified-results) below for the full cycle
breakdown from the latest run.

## Overview

Kyber key generation, encapsulation, and decapsulation rely heavily on the
NTT. This project implements a custom forward-only NTT accelerator in
BSV/Verilog, exposed as a burst-capable AXI4 slave peripheral on a
Chromite/InCore RISC-V SoC, with the goal of offloading NTT compute from
software while minimizing MMIO overhead.

**Core contributions:**
- Correct **negacyclic NTT** (mod x²⁵⁶+1, 7-stage Cooley-Tukey butterfly)
  with a bit-reversal counter (`br_cnt`) driving **runtime-computed
  twiddle factors** (sequential square-and-multiply, no ROM) — replacing
  an initial 8-stage cyclic implementation that caused Kyber key
  mismatches (KA ≠ KB).
- A burst-mode AXI4 slave (`NTTAXI4.bsv`) that accepts 16-beat INCR bursts
  on both the write and read channels, cutting AW/AR handshakes from 256
  to 16 per direction per NTT call.
- A 4-state control FSM (`IDLE → LOADING → RUNNING → DONE → IDLE`) with a
  done-latch register to reliably capture the Verilog core's single-cycle
  `done` pulse even while AXI rules are competing for scheduling.
- Per-call cycle/instruction profiling via RISC-V `rdcycle`/`rdinstret`
  CSRs, breaking down AXI-write, hardware-compute, and AXI-read phases for
  every one of the ~20 NTT calls in a full Kyber KEM cycle.
- An interrupt gateway for the NTT peripheral is already wired into the
  PLIC in `Soc.bsv` (`mkConnection(m_gateways[1].ma_input, ntt.interrupt)`)
  — the software driver currently polls `DONE` rather than using it; this
  is a straightforward follow-up (see [Status](#status-and-roadmap)).

## Verified Results

Latest full Kyber KEM run (keygen + encapsulation + decapsulation),
20 total NTT calls, 16 beats/burst × 16 bursts/NTT:

| Phase | NTT calls | NTT cycles | HW compute cycles |
|---|---|---|---|
| KeyGen | 8 | 137,047 | 19,638 |
| Encaps | 4 | 69,230 | 9,816 |
| Decaps | 8 | 136,546 | 19,633 |
| **Total** | **20** | **342,823** | **49,087** |

```
Total cycles (all Kyber ops)   : 5,143,018
Total NTT accelerator cycles   : 342,823
Total HW compute cycles        : 49,087   (~14% of NTT cycles)
Total AXI write cycles         : 106,889
Total AXI read cycles          : 128,614
Avg cycles / NTT call          : 17,141
Avg compute cycles / NTT call  : 2,454
Avg AXI cycles / NTT call      : 11,775

[MATCH] KA == KB  PASS
```

AXI traffic (write + read cycles) still accounts for roughly two-thirds
of every NTT call, confirming MMIO/bus overhead — not the butterfly
compute itself — as the dominant cost, consistent with the burst-mode
optimization already applied and motivating further work (see
[Status](#status-and-roadmap)).

## Repository Structure

```
.
├── hw/
│   ├── NTTAXI4.bsv               # AXI4 burst-mode slave, NTT control FSM (top)
│   ├── NTTWrapper.bsv            # BSV BVI wrapper around the Verilog core
│   ├── ntt_iterative_optimized.v # 7-stage negacyclic NTT core (Verilog, forward-only)
│   ├── Soc.bsv                   # SoC integration (AXI fabric, PLIC gateway wiring)
│   └── Soc.defines               # Address map (NTTBase/NTTEnd, PLIC, UART, CLINT, ...)
├── sw/
│   ├── ntt_kyber_hw.c             # Burst driver: pack/unpack + START/DONE handshake
│   ├── ntt_kyber_hw.h             # Register map, burst geometry, per-call stats structs
│   ├── poly.c                     # Kyber poly layer (poly_ntt calls ntt_kyber_hw_drive)
│   ├── reduce.c                   # Montgomery / Barrett reduction (software reference)
│   └── test_kyber.c               # Full KEM test harness, cycle profiling, KA==KB check
├── docs/
│   └── presentation/              # LaTeX Beamer slides (NITK Madrid theme)
├── sim/                            # VCS/Verilator simulation scripts & logs
├── synth/                          # Design Compiler (SCL 180nm) scripts, QOR
├── Makefile                        # Chromite SoC build/sim driver (see Build & Run)
└── README.md
```

## Architecture

```
RISC-V Core (Chromite/InCore SoC)
        │  AXI4  (base 0x0001_1400 – 0x0001_2FFF)
        ▼
 ┌───────────────────────┐
 │     NTTAXI4.bsv         │  FSM: IDLE → LOADING → RUNNING → DONE → IDLE
 │  (burst AXI4 slave,      │  done-latch captures 1-cycle Verilog `done` pulse
 │   16-beat INCR bursts)   │  interrupt → PLIC gateway (wired, unused by driver yet)
 │  ┌────────────────────┐ │
 │  │   NTTWrapper.bsv     │ │  BVI import of the Verilog core
 │  └─────────┬──────────┘ │
 │            ▼             │
 │  ntt_iterative_          │  7-stage Cooley-Tukey negacyclic butterfly,
 │  optimized.v              │  runtime square-and-multiply twiddle generation
 │                           │  (no ROM), forward-only (INTT stays in software)
 └───────────────────────┘
```

**Register map (base `0x0001_1400`):**
| Offset | Register | Access | Meaning |
|--------|----------|--------|---------|
| `0x000` | `CONTROL` | R/W | bit 0 = START, bit 1 = INVERSE (unused, forward-only core), bit 2 = BUSY, bit 3 = DONE |
| `0x004` | `STATUS`  | RO  | completed-operation count |
| `0x00C` | `PARAMS`  | RO  | `{ROOT[15:0], N[15:0]}` = `{17, 256}` |
| `0x400` | `DATA_IN` | W   | element `i` at `base + 0x400 + 4*i` |
| `0xC00` | `DATA_OUT`| R   | element `i` at `base + 0xC00 + 4*i` |

`CONTROL` write semantics: writing `START=1` while `IDLE` or `DONE` kicks
off a new NTT; writing `START=0` while in `DONE` returns the FSM to
`IDLE` — this second transition is the fix for a real deadlock (see
[Challenges](#challenges-debugging-steps--solutions), item 6).

## Implementation Steps

High-level path to reproduce this design end-to-end, from bare NTT math to
a working, burst-accelerated Kyber KEM cycle on the SoC.

### 1. Algorithm design
- Work out the negacyclic NTT for Kyber's ring `Z_3329[x]/(x²⁵⁶+1)`:
  7-stage Cooley-Tukey butterfly, with the correct **bit-reversed twiddle
  schedule** (`br_cnt`, starting at `br_inc(0) = 64`, *not* 0) — this is
  the detail that distinguishes Kyber's negacyclic zeta ordering from a
  textbook DIT NTT.
- Decide how twiddle factors will be produced in hardware: a precomputed
  ROM table, or computed on the fly. This design computes them on the fly
  via sequential square-and-multiply (`ROOT^br_cnt mod Q`, ≤7 cycles per
  butterfly group) to avoid a 128×14-bit ROM at the cost of ~46% more
  cycles.
- Choose a modular reduction strategy for the software side — Barrett
  reduction (see `reduce.c`) avoids a synthesized/software divider.

### 2. Standalone Verilog NTT core
- Implement a first working butterfly/NTT core in plain Verilog,
  independent of any bus or SoC.
- Verify plain output (`% Q`) against a golden software NTT reference
  before touching any bus logic.
  ```bash
  iverilog -o ntt_tb ntt_iterative_optimized.v ntt_tb.v && vvp ntt_tb
  verilator --cc ntt_iterative_optimized.v --exe ntt_tb.cpp
  ```
- Common early-stage bugs to expect and fix here (all hit during this
  project — see `ntt_iterative_optimized.v`'s header comment for the
  full list):
  - Twiddle values computed in an `initial` block — synthesis tools
    ignore `initial` blocks, so hardware sees all zeros. Move twiddle
    generation into a clocked FSM.
  - Textbook DIT twiddle index formula instead of Kyber's bit-reversal
    schedule.
  - `for` loops inside `always` blocks for load/store — zero-time in
    simulation, unroutable in real hardware. Replace with one
    coefficient per clock cycle via an index counter.
  - Stage count off by one for Kyber specifically (7 stages, not 8).
  - An unnecessary output bit-reversal permutation — after 7 correct CT
    stages the memory is *already* in Kyber's expected bit-reversed
    order; permuting again produces wrong output.

### 3. BSV wrapper / register interface (`NTTWrapper.bsv`)
- Wrap the Verilog core with a BVI (`import "BVI"`) module exposing
  `putData` / `result` / `done` methods matching the core's ports.
- Build a simple `Server#(NTTRequest, NTTResponse)` interface around it
  with a busy flag, so the wrapper can be dropped into different bus
  adapters without re-deriving the handshake logic each time.

### 4. AXI4 integration (`NTTAXI4.bsv`)
- Wrap the core behind an AXI4 slave port with a register map (`CONTROL`
  / `STATUS` / `PARAMS` / `DATA_IN` / `DATA_OUT`), get single-beat
  correctness first.
- Add burst support on both channels (`fn_axi4burst_addr`-driven address
  increment, `rg_wr_state`/`rg_rd_state` Idle↔Burst) once single-beat
  correctness is confirmed — this is what took write/read transactions
  from 256 handshakes down to 16.
  ```bash
  bsc -sim -g mkntt_axi4 -u NTTAXI4.bsv
  ```

### 5. SoC integration (`Soc.bsv` / `Soc.defines`)
- Add the peripheral's address window (`NTTBase`/`NTTEnd`) and slave
  index to `Soc.defines`, instantiate `mkntt_axi4` in `Soc.bsv`, and wire
  it into the AXI4 fabric's slave map.
- Wire the peripheral's `interrupt` line into an unused PLIC gateway so
  interrupt-driven completion is available even if the driver still
  polls initially.
- Rebuild the full SoC simulation model using the project's real
  `Makefile` targets (see [Build & Run](#build--run)):
  ```bash
  make generate_verilog
  make link_verilator
  ```

### 6. Software driver (`ntt_kyber_hw.c` / `ntt_kyber_hw.h`)
- Write MMIO read/write helpers for `CONTROL`/`DATA_IN`/`DATA_OUT`.
- Implement `axi_burst_write`/`axi_burst_read` helpers matching the
  hardware's burst geometry (`BURST_LEN = 16`, `NUM_BURSTS = N/BURST_LEN`
  — defined once in the header and never duplicated in the driver).
- Convert signed `int16_t` coefficients to their positive residue mod Q
  before writing to hardware (`v < 0 ? v + Q : v`) — hardware treats the
  32-bit register as unsigned, so raw two's-complement values are wrong.
- Add a `START`/`DONE` polling loop with a bounded timeout, and instrument
  every phase with `rdcycle`/`rdinstret` for later profiling.

### 7. Kyber KEM integration (`poly.c` / `test_kyber.c`)
- Route `poly_ntt()` through `ntt_kyber_hw_drive()` instead of the
  software NTT, one polynomial at a time.
- Run full KeyGen → Encaps → Decaps and check `KA == KB` before doing any
  further optimization — correctness first, always.

### 8. Verification
- Cross-check hardware NTT output against a golden software NTT reference
  across many random vectors.
- Simulate with Verilator for fast iteration; VCS/other sign-off tools
  for closer-to-silicon behavior when needed.

### 9. Profiling
- Instrument the driver with `rdcycle`/`rdinstret` around AXI-write,
  compute (`DONE` poll), and AXI-read phases per call, and accumulate into
  global stats (`g_ntt_hw_stats`) for a full-run summary like the one in
  [Verified Results](#verified-results).

### 10. Iterate on the real bottleneck
- Once correctness holds, use the profiling data to find where cycles
  actually go — in this design, AXI write+read cycles still dominate the
  per-call cost even after burst coalescing, which is the natural next
  target (see [Status](#status-and-roadmap)).

## Build & Run

The project's `Makefile` drives the whole Chromite SoC build/sim flow —
BSV compile, Verilog generation, and linking against a chosen simulator —
plus benchmark-specific targets that build and run individual test
programs.

```bash
# Default build: generate Verilog + link with Verilator + generate boot files
make            # == make generate_verilog link_verilator generate_boot_files

# Regenerate Verilog from BSV sources only
make generate_verilog

# Link against a specific simulator
make link_verilator          # Verilator (fast, default)
make link_verilator_elf      # Verilator + ELF memory loader
make link_verilator_gdb      # Verilator + remote-bitbang VPI for GDB/JTAG debug
make link_vcs                # Synopsys VCS
make link_ncverilog          # Cadence NC-Verilog
make link_msim                # Mentor ModelSim

# Run a specific benchmark (each builds its own ELF under benchmarks/ and runs it)
make hello        # hello-world sanity check
make ntt          # standalone NTT benchmark
make kyber        # full Kyber KEM test (hardware-accelerated NTT), incl. KA==KB check
make kyber_sw     # Kyber KEM test, software-only NTT (baseline for comparison)
make kyber-kat    # Kyber Known-Answer-Test vectors
make dhrystone    # Dhrystone benchmark
make coremarks    # CoreMark benchmark

# Debug build (Verilator + GDB/JTAG remote-bitbang)
make gdb          # == make generate_verilog link_verilator_gdb generate_boot_files

# Package a build for handoff
make drop         # tar -czf build-<date>.tar.gz build/

# Clean everything
make clean
```

> The handwritten `ntt_iterative_optimized.v` and other BVI-imported
> Verilog files are copied into the generated Verilog directory by
> `generate_verilog` itself (via `listVlogFiles.tcl`) — if you add a new
> BVI-imported `.v` file and it isn't picked up, check that script rather
> than assuming a manual copy step is needed.

Raw commands for reference / manual debugging, outside the Makefile flow:

```bash
# BSV compile (bsc) for a single module
bsc -sim -g mkntt_axi4 -u NTTAXI4.bsv

# ASIC synthesis (Design Compiler, SCL 180nm SS corner)
dc_shell -f synth/run_dc.tcl

# Verify symbol / buffer addresses in a compiled benchmark ELF
riscv64-unknown-elf-nm benchmarks/output/kyber.riscv | grep -i ntt
```

## Status and Roadmap

- [x] Correct negacyclic NTT implementation, runtime twiddle generation
- [x] Burst-mode AXI4 slave (16-beat INCR bursts on write & read)
- [x] 4-state control FSM with done-latch, including the `DONE→IDLE`
      deadlock fix (see Challenges, item 6)
- [x] Per-call profiling (cycle/instruction counts) across a full KEM run
- [x] Full Kyber KEM round-trip verified: **`KA == KB` PASS**
      (20 NTT calls, 342,823 NTT-accelerator cycles, 5,143,018 total
      Kyber cycles — see [Verified Results](#verified-results))
- [x] PLIC interrupt gateway wired for the NTT peripheral (`Soc.bsv`)
- [ ] Switch the driver from `DONE` polling to the already-wired PLIC
      interrupt
- [ ] Reduce AXI write/read cycles further — they still account for
      roughly two-thirds of every NTT call even after burst coalescing
      (candidates: wider/dual-coefficient packing per beat, deeper
      bursts, ping-pong double buffering to overlap load/compute/store)
- [ ] DC synthesis timing closure — hold violations pending
      `set_fix_hold` incremental compile
- [ ] Hardware Keccak/SHAKE accelerator — profiling showed Keccak/SHAKE
      dominates overall Kyber cycles far more than the NTT does, so this
      is higher-leverage than further NTT-only tuning
- [ ] Custom instruction for NTT (see Related Work)

## Challenges, Debugging Steps & Solutions

This section documents the major bugs encountered across the BSV
peripheral, C driver, and Verilog NTT core, along with how each was
diagnosed and fixed. Kept here as a debugging log / reference for anyone
extending this design.

### 1. Kyber key mismatch (`KA != KB`) — cyclic vs. negacyclic NTT
- **Symptom:** Decapsulated shared secret didn't match the encapsulated one.
- **Diagnosis:** Root NTT implementation used an 8-stage *cyclic* NTT
  (mod x²⁵⁶−1) instead of the 7-stage *negacyclic* NTT (mod x²⁵⁶+1)
  required by Kyber's ring structure, with a textbook (non-Kyber) twiddle
  index formula.
- **Solution:** Rewrote the butterfly network as a 7-stage negacyclic NTT
  driven by a bit-reversal counter (`br_cnt`) starting at 64, matching
  Kyber's reference `zetas[1..127]` schedule exactly. This is now
  confirmed resolved end-to-end — `KA == KB` passes on a full KEM run.

### 2. Twiddle factors invisible in hardware (`initial` block)
- **Symptom:** Simulation matched behaviorally, but the design would have
  synthesized with all-zero twiddle values.
- **Diagnosis:** The original implementation computed the twiddle table in
  an `initial` block, which synthesis tools do not implement in hardware.
- **Solution:** Replaced it with a clocked square-and-multiply FSM (state
  `ZETA`) that computes `ROOT^br_cnt mod Q` in ≤7 cycles before each
  butterfly group — fully synthesizable, no ROM.

### 3. Unrouteable `for` loops inside `always` blocks
- **Symptom:** Load/store stages behaved correctly only in simulation.
- **Diagnosis:** The LOAD and STORE states used `for (i=0;i<N;i++)` loops
  inside a clocked `always` block — zero simulation time, not synthesizable
  as real sequential hardware.
- **Solution:** Replaced with an `i_ptr` counter, moving one coefficient
  per clock cycle.

### 4. Extra output bit-reversal permutation
- **Symptom:** NTT output didn't match the reference ordering.
- **Diagnosis:** The core applied `data_out[i] = mem[bit_reverse(i,8)]` on
  output, but after 7 correct Cooley-Tukey stages the memory is *already*
  in Kyber's bit-reversed order — the extra permutation double-reversed it.
- **Solution:** Output `mem[i]` directly, no additional permutation.

### 5. Negative `int16_t` sent as raw bit pattern
- **Symptom:** Incorrect results specifically for coefficients with
  negative values.
- **Diagnosis:** Negative `int16_t` coefficients were being written to the
  32-bit `DATA_IN` register as their raw two's-complement bit pattern,
  which the (unsigned) hardware register interpreted as a large positive
  value.
- **Solution:** `pack_data_in_burst()` in `ntt_kyber_hw.c` now converts
  every coefficient to its positive residue mod Q (`v < 0 ? v + Q : v`)
  before writing, as a separate CPU-only pass before any AXI traffic.

### 6. `DONE → IDLE` deadlock on `CONTROL` writes
- **Symptom:** The first NTT call completed fine, but every call after it
  hung forever waiting for `DONE` to clear.
- **Diagnosis:** The FSM only handled `START=1` while `IDLE`/`DONE` to
  kick off a new NTT; there was no transition handling `START=0` while in
  `DONE`, so the FSM (and therefore the `DONE` status bit) never returned
  to `IDLE` after the first call — deadlocking the driver's reset
  handshake on every subsequent call.
- **Solution:** Added the missing transition in `do_write()`:
  `START=0` while in `DONE` → `rg_state <= IDLE`.

### 7. Missing `done`-pulse capture under AXI contention
- **Symptom:** Intermittent missed completions when AXI read/write rules
  were also firing.
- **Diagnosis:** The Verilog core's `done` signal is only a single-cycle
  pulse; a rule that both checked `done()` and consumed the result in the
  same cycle could lose the pulse if it lost scheduling priority to a
  competing AXI rule that cycle.
- **Solution:** Split into two rules — `rl_latch_done` latches the pulse
  into a `rg_done_latch` register the instant it's seen, and
  `rl_collect_from_ntt` reads the (still-valid) result one cycle later,
  independent of AXI rule scheduling that cycle.

### 8. AXI overhead dominating cycle count even after burst coalescing
- **Symptom:** Even with 16-beat bursts, most of each NTT call's cycles
  are still spent on AXI traffic rather than hardware compute.
- **Diagnosis:** Per-call profiling across a full KEM run shows AXI write
  cycles (106,889 total) and AXI read cycles (128,614 total) together
  account for roughly two-thirds of the 342,823 total NTT-accelerator
  cycles, versus only 49,087 cycles (~14%) of actual hardware compute.
- **Status:** Correctness is verified (`KA == KB` PASS); this remains the
  primary performance target — see [Status](#status-and-roadmap) for
  candidate next steps (wider per-beat packing, deeper bursts, double
  buffering).

### 9. Profiling infrastructure gave misleading numbers
- **Symptom:** Cycle/instruction counts didn't match expected behavior
  during early instrumentation.
- **Diagnosis (multiple causes):**
  - Reset calls for `rdcycle`/`rdinstret` were placed *inside* the timed
    window, inflating counts.
  - The compiler eliminated "dead" CSR reads, silently changing pipeline
    behavior around the measurement.
  - A single before/after pair couldn't separate individual phases
    (pack, start-write, compute, unpack) from each other.
- **Solution:** Timed each phase with its own `hw_rdcycle()`/
  `hw_rdinstret()` snapshot pair (see `ntt_kyber_hw_drive()`), keeping
  resets and unrelated work outside every timed window.

### 10. BSV proviso compile error (`T0065`)
- **Symptom:** `bsc` compile failure: `Add#(d__, addr, data)` proviso
  could not be satisfied.
- **Diagnosis:** `mkntt_axi4` needs explicit type-level constraints
  relating address and data widths for its address-truncation and
  strobe-handling logic to type-check.
- **Solution:** Added the required provisos to the module signature:
  `Add#(a__, 12, addr)`, `Add#(b__, 16, data)`, `Add#(c__, 32, data)`,
  `Mul#(8, TDiv#(data,8), data)`.

### 11. Design Compiler synthesis failures
- **Symptom:** `dc_shell` synthesis of `mkSoc` on the shared server failed
  with invalid flags, references to non-existent `hdlin*` variables, and
  `OPT-1603` virtual memory errors.
- **Diagnosis:** Script used flags/variables not valid for the installed
  DC version; `OPT-1603` traced to virtual memory contention from other
  jobs on the shared server.
- **Solution:** Corrected flag/variable usage; scheduled synthesis runs
  to avoid resource contention; set minimum acceptable synthesis effort
  levels for academic/tapeout-quality QOR reports.

### 12. VCS simulation killed by `SIGHUP`
- **Symptom:** Long-running SPI Flash / SAIF-generation simulation
  terminated unexpectedly.
- **Diagnosis:** Most likely cause was a VCS license timeout combined
  with the simulation not being detached from the terminal session;
  `saif_gen.sh` was also missing the `-power` compile flag and correct
  SAIF runtime flags.
- **Solution:** Fixed `saif_gen.sh` (added `-power`, ran with `nohup ... &`
  to survive shell hangup, added missing SAIF runtime flags).

### 13. Linker script — missing `.rodata`
- **Symptom:** Spurious AXI deadlocks and unexpected `START` triggers on
  the NTT peripheral.
- **Diagnosis:** Missing `.rodata` section in the linker script caused
  the stack pointer to be placed inside the NTT peripheral's AXI address
  window, so normal stack writes were hitting peripheral registers.
- **Solution:** Added the missing `.rodata` section to the linker script
  to correctly relocate the stack outside the peripheral's address range.

## Related Work

An ongoing effort to reduce the execution cycle by increasing the beats,
switching the driver to the already-wired PLIC interrupt instead of
polling, and implementing a custom instruction for NTT.

## Acknowledgements

- Prof. M. S. Bhat (NITK Surathkal, internal advisor)
- Tripti S. Warrier (CUSAT, external advisor)
- CArS Lab, CUSAT
- InCore Semiconductors Pvt. Ltd.
