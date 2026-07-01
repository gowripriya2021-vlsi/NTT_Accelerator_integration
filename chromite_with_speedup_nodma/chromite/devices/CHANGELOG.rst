CHANGELOG
=========

This project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`_.

[2.4.0] - 2022-05-19
--------------------
- rv32 related changes to debugger

[2.3.1] - 2022-03-21
--------------------
- Fix provisos for RV32
- Add pragma to remove warning while compile

[2.3.0] - 2022-03-18
--------------------
- Add elfmem module to enable seeding memory from elfs during simulation.

[2.2.3] - 2022-03-01
--------------------
- add support for compiling debug in rv32 mode.

[2.2.2] - 2022-02-23
--------------------
- CLINT's timecmp reset value is now a parameter.

[2.2.1] - 2021-10-23
--------------------
- Fix burst request issue in ROM

[2.2.0] - 2021-10-23
--------------------
- Adding debugger compatible with stable version 1.0 

[2.1.0] - 2021-10-23
--------------------
- Design of aclint.

[2.0.0] - 2021-10-08
--------------------
- Addition of permission fields to Write and read of DCBus interface

[1.6.1] - 2021-10-07
--------------------
- Addition of Protected OCM as devices.

[1.6.0] - 2021-09-14
--------------------
- fix plic issue to be compatible with linux driver
- added new gateway module (pure bluespec version)

[1.5.1] - 2021-08-30
--------------------
- fixes in pwm with syncronizer
- Added SPI with Controller(Master) and Peripheral(Slave) Functionality

[1.5.0] - 2021-08-27
--------------------
- fixes in ram[1/2]rw modules based on the new memconfig module from bsvwrappers repo

[1.4.8] - 2021-08-16
--------------------
- UART Break error and Frame error bug fix

[1.4.7] - 2021-07-30
--------------------
- SPI Master Bug fixes and Feature Additions

[1.4.6] - 2021-06-15
--------------------
- Module Name fix in gateway

[1.4.5] - 2021-06-10
--------------------
- Gateway addition to PLIC
- Addition of Interrupt service complete sideband in PLIC interface

[1.4.4] - 2021-05-26
--------------------
- SPI Bug Fix (Rx clear, pulsed delay clk, Implicit conidtion on reset)
- Added Sync Disable bit

[1.4.3] - 2021-05-26
--------------------

- allow multiple claims from target
- allow claiming when source interrupt is disabled or not pending
- do not write the pending interrupt until cleared and not busy

[1.4.2] - 2021-04-27
--------------------
- Redesign of SPI internal architecture. [Bug Fix]
- Synchronizing PWM interrupts with PWM output and removing ClockDiv. [Bug Fix]

[1.4.1] - 2021-03-08
--------------------

- Renaming qspi ports
- fixed logger statements so that verilator no longer complaints
- adding link_verilator as part of the ci.

[1.4.0] - 2021-02-24
--------------------

- Adding QSPI revamp code.

[1.3.0] - 2021-01-13
--------------------

- Adding SPI code.


[1.2.0] - 2020-12-05
--------------------
- PLIC max-priority extraction function now uses vector folding functions in bluespec to enable
compiling designs with higher interrupt sources.

[1.1.2] - 2020-09-15
--------------------
- GPIO interrupts to PLIC parameterized

[1.1.1] - 2020-09-14
--------------------

- updated incore licensing terms to SHL
- updates pwm licensing terms
- updated ci for pwm compilation

[1.1.0] - 2020-09-14
--------------------

- Adding PWM code.

[1.0.8] - 2020-09-12
--------------------

- Fixed state machine for the xilinx jtag dtm to be compatible with the current upstream
riscv-openocd

[1.0.7] - 2020-07-17
--------------------

- Adding UART16550 code.

[1.0.6] - 2020-06-29
--------------------

- fixed bug in error status reg update.

[1.0.5] - 2020-06-27
--------------------

- fixed burst mode support in ram\*rw devices. The axi4 wrapper now prevents latching a new request
  to the ram if a stall occurs in the response channel.

[1.0.4] - 2020-06-26
--------------------

- Bug fixes in uart. Clearing of interrupts logic fixed.
- Bug fixes in plic. Accessing non-existing IEs no longer generates traps but instead
  returns zeros
- Adding a simple boot configuration device.

[1.0.3] - 2020-06-17
--------------------

- Changed DC Bus subinterface names
- Added RX and TX threshold features in UART
- Added interrupt support in UART

[1.0.2] - 2020-05-20
--------------------

-  change initial value of mtimecmp to avoid generating an interrupt at reset.
-  reading src_id 0 in plic no longer generates an error.

[1.0.1] - 2020-05-18
--------------------

- In CLINT the DCBus parameter for offset should be 3 instead of 2 indicating the config registers
  are at 8 byte boundaries

[1.0.0] - 2020-04-26
--------------------

- Adding new PLIC with DCBus support which is compatible with the riscv-plic-spec
- Adding clint, uart and gpios with DCBus support
- Adding single and double ported RAMs
- Adding roms
