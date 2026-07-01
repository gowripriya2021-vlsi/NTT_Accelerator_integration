// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: instances of all the modules for instruciton tlbs

*/
package sa_itlb_instances ;

`ifdef async_reset
  import RegOverrides  :: *;
`endif
import FIFOF          :: * ;
import Vector         :: * ;
import SpecialFIFOs   :: * ;
import FIFOF          :: * ;
`include "Logger.bsv"
`ifdef hypervisor 
	import split_tlb_hypervisor ::*;
`else
	import split_tlb      :: * ;
`endif
import mmu_types      :: * ;

`ifdef sv32
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
  module mkitlb_4kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(1, `ifdef hypervisor 1, `endif `itlb_ways_4kb, `itlb_sets_4kb, 20, 12, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(KB_4, `itlb_rep_alg_4kb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
	module mkitlb_4mb#(parameter Bool complex_sfence)(Ifc_split_tlb#(1, `ifdef hypervisor 1, `endif `itlb_ways_4mb, `itlb_sets_4mb, 10, 22, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(MB_4, `itlb_rep_alg_2mb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
	
  	
`endif
	
`ifdef sv39
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
	module mkitlb_4kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `itlb_ways_4kb, `itlb_sets_4kb, 27, 12, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(KB_4, `itlb_rep_alg_4kb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
	module mkitlb_2mb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `itlb_ways_2mb, `itlb_sets_2mb, 18, 21, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(MB_2, `itlb_rep_alg_2mb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
	module mkitlb_1gb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `itlb_ways_1gb, `itlb_sets_1gb, 9,  30, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(GB_1, `itlb_rep_alg_1gb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
`ifdef svnapot	
	`ifdef itlb_noinline
		(*synthesize*)
	`endif 
	module mkitlb_64kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif  `itlb_ways_64kb, `itlb_sets_64kb, 23, 16, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
			let ifc();
			mk_split_tlb#(KB_64, `itlb_rep_alg_64kb, "I-", complex_sfence) _temp(ifc);
			return (ifc);
	endmodule
`endif	

`endif

`ifdef sv48
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
  module mkitlb_4kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `itlb_ways_4kb, `itlb_sets_4kb, 36, 12, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(KB_4, `itlb_rep_alg_4kb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
	module mkitlb_2mb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `itlb_ways_2mb, `itlb_sets_2mb, 27, 21, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(MB_2, `itlb_rep_alg_2mb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
	module mkitlb_1gb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `itlb_ways_1gb, `itlb_sets_1gb, 18, 30, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(GB_1, `itlb_rep_alg_1gb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
  module mkitlb_512gb#(parameter Bool complex_sfence)(Ifc_split_tlb#(9, `ifdef hypervisor 9, `else 0, `endif `itlb_ways_512gb, `itlb_sets_512gb, 9,  39, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(GB_512, `itlb_rep_alg_512gb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
`ifdef svnapot	
	`ifdef itlb_noinline
		(*synthesize*)
	`endif 
	module mkitlb_64kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 9, `else 0,  `endif  `itlb_ways_64kb, `itlb_sets_64kb, 32, 16, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
			let ifc();
			mk_split_tlb#(KB_64, `itlb_rep_alg_64kb, "I-", complex_sfence) _temp(ifc);
			return (ifc);
	endmodule
`endif

`endif

`ifdef sv57
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
  module mkitlb_4kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `itlb_ways_4kb, `itlb_sets_4kb, 45, 12, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(KB_4, `itlb_rep_alg_4kb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
	module mkitlb_2mb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `itlb_ways_2mb, `itlb_sets_2mb, 36, 21, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(MB_2, `itlb_rep_alg_2mb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
	module mkitlb_1gb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `itlb_ways_1gb, `itlb_sets_1gb, 27, 30, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(GB_1, `itlb_rep_alg_1gb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
  module mkitlb_512gb#(parameter Bool complex_sfence)(Ifc_split_tlb#(9, `ifdef hypervisor 9, `else 0,  `endif `itlb_ways_512gb, `itlb_sets_512gb, 18, 39, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(GB_512, `itlb_rep_alg_512gb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
  `ifdef itlb_noinline
    (*synthesize*)
  `endif
  module mkitlb_256tb#(parameter Bool complex_sfence)(Ifc_split_tlb#(10, `ifdef hypervisor 10, `else 0,  `endif `itlb_ways_256tb, `itlb_sets_256tb, 9, 48, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
		let ifc();
		mk_split_tlb#(TB_256, `itlb_rep_alg_256tb, "I-", complex_sfence) _temp(ifc);
		return (ifc);
	endmodule
`ifdef svnapot	
	`ifdef itlb_noinline
		(*synthesize*)
	`endif 
	module mkitlb_64kb#(parameter Bool complex_sfence)(Ifc_split_tlb#(8, `ifdef hypervisor 8, `else 0, `endif `itlb_ways_64kb, `itlb_sets_64kb, 41, 16, `subvpn, `xlen, `ppnsize, `lastppnsize, `vaddr, `paddr, `max_varpages, `asidwidth, `ifdef hypervisor `vmidwidth, `endif  `satp_mode_size, `ifdef svnapot 1 `else 0 `endif ));
			let ifc();
			mk_split_tlb#(KB_64, `itlb_rep_alg_64kb, "I-", complex_sfence) _temp(ifc);
			return (ifc);
	endmodule
`endif	
	
`endif
endpackage:sa_itlb_instances
