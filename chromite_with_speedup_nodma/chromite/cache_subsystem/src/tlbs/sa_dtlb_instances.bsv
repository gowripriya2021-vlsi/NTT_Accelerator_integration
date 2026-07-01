// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: instances of all the modules

*/
package sa_dtlb_instances ;

`ifdef async_reset
  import RegOverrides  :: *;
`endif
import FIFOF          :: * ;
import Vector         :: * ;
import SpecialFIFOs   :: * ;
import FIFOF          :: * ;
`include "Logger.bsv"

import mmu_types      :: * ;
`ifdef hypervisor 
	import split_tlb_hypervisor ::*;
`else
	import split_tlb      :: * ;
`endif


`ifdef sv32
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
  module mkdtlb_4kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(1, `ifdef hypervisor 1, `else 0  `endif `dtlb_ways_4kb, `dtlb_sets_4kb, 20, 12, `xlen, `ppnsize, 26, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size , `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(KB_4, `dtlb_rep_alg_4kb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
	module mkdtlb_4mb#(parameter Bool complex_sfence)(Ifc_split_tlb#(1, `ifdef hypervisor 1, `else 0  `endif `dtlb_ways_4mb, `dtlb_sets_4mb, 10, 22, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size , `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(MB_4, `dtlb_rep_alg_2mb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  	
`endif
	
`ifdef sv39
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif	
  module mkdtlb_4kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8,`else 0, `endif `dtlb_ways_4kb, `dtlb_sets_4kb, 27, 12, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(KB_4, `dtlb_rep_alg_4kb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
	module mkdtlb_2mb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8,`else 0, `endif `dtlb_ways_2mb, `dtlb_sets_2mb, 18, 21, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size , `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(MB_2, `dtlb_rep_alg_2mb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
	module mkdtlb_1gb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8,`else 0, `endif `dtlb_ways_1gb, `dtlb_sets_1gb, 9,  30, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(GB_1, `dtlb_rep_alg_1gb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
`ifdef svnapot
	`ifdef dtlb_noinline
		(*synthesize*)
	`endif 
	module mkdtlb_64kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8,`else 0, `endif  `dtlb_ways_64kb, `dtlb_sets_64kb, 23, 16, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
			let ifc();
			mk_split_tlb#(KB_64, `dtlb_rep_alg_64kb, "D-", complex_sfence) _temp(ifc);
			return (ifc);
	endmodule
`endif	

`endif

`ifdef sv48
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
  module mkdtlb_4kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `dtlb_ways_4kb, `dtlb_sets_4kb, 36, 12, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(KB_4, `dtlb_rep_alg_4kb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
	module mkdtlb_2mb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `dtlb_ways_2mb, `dtlb_sets_2mb, 27, 21, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(MB_2, `dtlb_rep_alg_2mb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
	module mkdtlb_1gb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `dtlb_ways_1gb, `dtlb_sets_1gb, 18, 30, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(GB_1, `dtlb_rep_alg_1gb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
  module mkdtlb_512gb#(parameter Bool complex_sfence)(Ifc_split_tlb#(9, `ifdef hypervisor 9, `else 0, `endif `dtlb_ways_512gb, `dtlb_sets_512gb, 9,  39, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(GB_512, `dtlb_rep_alg_512gb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
`ifdef svnapot	
	`ifdef dtlb_noinline
		(*synthesize*)
	`endif 
	module mkdtlb_64kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 9, `else 0,  `endif  `dtlb_ways_64kb, `dtlb_sets_64kb, 32, 16, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
			let ifc();
			mk_split_tlb#(KB_64, `dtlb_rep_alg_64kb, "D-", complex_sfence) _temp(ifc);
			return (ifc);
	endmodule
`endif

`endif

`ifdef sv57
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
  module mkdtlb_4kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `dtlb_ways_4kb, `dtlb_sets_4kb, 45, 12, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(KB_4, `dtlb_rep_alg_4kb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
	module mkdtlb_2mb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `dtlb_ways_2mb, `dtlb_sets_2mb, 36, 21, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(MB_2, `dtlb_rep_alg_2mb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
	module mkdtlb_1gb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `dtlb_ways_1gb, `dtlb_sets_1gb, 27, 30, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(GB_1, `dtlb_rep_alg_1gb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
  module mkdtlb_512gb#(parameter Bool complex_sfence)(Ifc_split_tlb#(9, `ifdef hypervisor 9, `else 0,  `endif `dtlb_ways_512gb, `dtlb_sets_512gb, 18, 39, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(GB_512, `dtlb_rep_alg_512gb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef dtlb_noinline
    (*synthesize*)
  `endif
  module mkdtlb_256tb#(parameter Bool complex_sfence)(Ifc_split_tlb#(10, `ifdef hypervisor 10, `else 0,  `endif `dtlb_ways_256tb, `dtlb_sets_256tb, 9, 48, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(TB_256, `dtlb_rep_alg_256tb, "D-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
`ifdef svnapot	
	`ifdef dtlb_noinline
		(*synthesize*)
	`endif 
	module mkdtlb_64kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `dtlb_ways_64kb, `dtlb_sets_64kb, 41, 16, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
			let ifc();
			mk_split_tlb#(KB_64, `dtlb_rep_alg_64kb, "D-", complex_sfence) _temp(ifc);
			return (ifc);
	endmodule
`endif	
	
`endif
endpackage:sa_dtlb_instances
