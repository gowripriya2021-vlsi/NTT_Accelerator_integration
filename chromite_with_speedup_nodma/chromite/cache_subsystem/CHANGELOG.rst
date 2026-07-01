CHANGELOG
=========

This project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`_.

[2.0.3] - 2022-09-14
--------------------
- bug fix by adding ifdef supervisor wherever necessary

[2.0.2] - 2022-08-25
--------------------
- added support for hypervisor in set-associative tlbs.
- added vmidwidth as macro

[2.0.1] - 2022-08-16
--------------------
- support for physical address of 56.

[2.0.0] - 2022-08-09
--------------------
- hypervisor support for ptwalk, created a new package for ptwalk_hypervisor.
- added dummy tlbs 
- added fully associative tlbs with hypervisor support

[1.2.5] - 2022-06-22
--------------------
- Added `RegOverrides` import to all modules.

[1.2.4] - 2022-05-11
--------------------
- Added satp_mode_size as a interface parameter to mkptwalk_rv module

[1.2.3] - 2022-04-09
--------------------
- updated pmp checks algo according to specs, if no PMP entry matches an S-mode or U-mode access, but at least one PMP entry is implemented, the access fails.

[1.2.2] - 2022-04-09
--------------------
- LR instruction is treated as same as instruction with LOAD access rather that ATOMIC inside TLB, so that an fault/trap
	is Load_pagefault/Load_access_fault which is according to spec sheet

[1.2.1] - 2022-03-31
--------------------

- Checks for page fault moved to sa_dtlb from split_tlb
- Removed the cause field in TLB entry from set-associative TLBs
- Added SVNAPOT support in set and fully associative TLBs. For set associative added a 
	new TLB module to cache the NAPOT PTEs and for fully associative TLBs created a 
	different mask to store and cache the NAPOT PTEs.
- Added "N" bit as a part of response of PTW to TLBs to identify the given response is 
	a NAPOT PTE or not
- Changed the SVNNAPOT macro declaration 
- Added control of sfence complexity(simple/complex) for TLB as a module paramerter to TLBs
- Support for complex sfence in STAGE-3 and STAGE-0 of the pipeline
-	Support for user defined sfence statergies(complex/simple) for ITLB and DTLB. Complex sfence is 
	only available if simple_sfence is not defined

[1.2.0] - 2022-03-21
--------------------

- support sv32, sv39, sv48 , sv57
- support svnapot
- fully-associative and set-associative variants of TLBs now available
- cleaned up ptwalk with parameterized version
- all csr fields to be picked from request instead of side-bands

[1.1.0] - 2022-03-02
--------------------

- Modified icache responsewidth to cacheline size
- CWF no longer supported(properly) in icache
- Each IO request is of cacheline size
- Added IO buffer
- Fixed DCache for RV32 

[1.0.1] - 2020-06-18
--------------------

- increased random test size for dcache
- added missing ifdef supervisor macro


[1.0.0] - 2020-05-07
--------------------

- io responses fro the caches are assumed to hold the required bytes at the respective bit 
  offsets. Earlier it was assumed the controller would do the re-alignment and send the bytes in 
  the lower order bits to the cache. The re-alignment is now being handled by the caches themselves.
