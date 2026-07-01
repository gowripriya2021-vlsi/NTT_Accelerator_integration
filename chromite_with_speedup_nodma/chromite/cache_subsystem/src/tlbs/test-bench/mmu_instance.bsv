// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Tuesday 25 January 2022 02:19:51 PM

*/
package mmu_instance;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;
  // `include "mmu.defines"

  `include "Logger.bsv"

  /*import ptwalk_rv    :: * ;
  (*synthesize*)
  module mkinstance(Ifc_ptwalk_rv);
    let ifc();
    mkptwalk_rv _temp(ifc);
    return (ifc);
  endmodule*/

`ifdef supervisor
  `ifdef hypervisor
    import ptwalk_rv_hypervisor    :: * ;
    (*synthesize*)
    module mkptw_instance(Ifc_ptwalk_rv#(`xlen, `paddr, `max_varpages, `ppnsize, `lastppnsize, `subvpn, `page_offset, 
        `asidwidth, `satp_mode_size,  `ifdef svnapot 1 `else 0 `endif ));
      let ifc();
      mkptwalk_rv#(1) _temp(ifc);
      return (ifc);
    endmodule 
    `ifdef dummy
      import dummy_dtlb_hypervisor ::*;
      (*synthesize*)
      module mkdummy_dtlb_instance(Ifc_dtlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vmidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn, `ifdef svnapot 1 `else 0 `endif )); 
        let ifc();
        mkdtlb#(1, True) _temp(ifc);
        return (ifc);
      endmodule

      import dummy_itlb_hypervisor ::*;
      (*synthesize*)
      module mkdummy_itlb_instance(Ifc_itlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vmidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn, `ifdef svnapot 1 `else 0 `endif )); 
        let ifc();
        mkitlb#(1, True) _temp(ifc);
        return (ifc);
      endmodule
    `elsif fa
      import fa_dtlb_hypervisor  :: * ;
      (*synthesize*)
      module mkdtlb_instance(Ifc_dtlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vmidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn,  `ifdef svnapot 1 `else 0 `endif ));
        let ifc();
        mkdtlb#(1, True) _temp(ifc);
        return (ifc);
      endmodule

      import fa_itlb_hypervisor  :: * ;
      (*synthesize*)
      module mkitlb_instance(Ifc_itlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vmidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn,  `ifdef svnapot 1 `else 0 `endif ));
        let ifc();
        mkitlb#(1, True) _temp(ifc);
        return (ifc);
      endmodule
    `elsif sa
      import sa_dtlb_hypervisor      :: * ;
      (*synthesize*)
      module mkdtlb_instance(Ifc_dtlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vmidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn, `ifdef svnapot 1 `else 0 `endif )); 
        let ifc();
        mkdtlb#(1, True) _temp(ifc);
        return (ifc);
      endmodule 

      import sa_itlb_hypervisor      :: * ;
      (*synthesize*)
      module mkitlb_instance(Ifc_itlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vmidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn,  `ifdef svnapot 1 `else 0 `endif )); 
        let ifc();
        mkitlb#(1, True) _temp(ifc);
        return (ifc);
      endmodule
    `endif 
  `else 
    import ptwalk_rv_supervisor    :: * ;
    (*synthesize*)
    module mkptw_instance(Ifc_ptwalk_rv#(`xlen, `paddr, `max_varpages, `ppnsize, `lastppnsize, `subvpn, `page_offset, 
        `asidwidth, `satp_mode_size,  `ifdef svnapot 1 `else 0 `endif ));
      let ifc();
      mkptwalk_rv#(1) _temp(ifc);
      return (ifc);
    endmodule
    `ifdef dummy
      import dummy_dtlb_supervisor ::*;
      (*synthesize*)
      module mkdummy_dtlb_instance(Ifc_dtlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn, `ifdef svnapot 1 `else 0 `endif )); 
        let ifc();
        mkdtlb#(1, True) _temp(ifc);
        return (ifc);
      endmodule

      import dummy_itlb_supervisor ::*;
      (*synthesize*)
      module mkdummy_itlb_instance(Ifc_itlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn, `ifdef svnapot 1 `else 0 `endif )); 
        let ifc();
        mkitlb#(1, True) _temp(ifc);
        return (ifc);
      endmodule
    `elsif fa
      import fa_dtlb  :: * ;
      (*synthesize*)
      module mkdtlb_instance(Ifc_dtlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn,  `ifdef svnapot 1 `else 0 `endif ));
        let ifc();
        mkdtlb#(1, True) _temp(ifc);
        return (ifc);
      endmodule

      import fa_itlb  :: * ;
      (*synthesize*)
      module mkitlb_instance(Ifc_itlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn,  `ifdef svnapot 1 `else 0 `endif ));
        let ifc();
        mkitlb#(1, True) _temp(ifc);
        return (ifc);
  endmodule
    `elsif sa
      import sa_dtlb      :: * ;
      (*synthesize*)
      module mkdtlb_instance(Ifc_dtlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn, `ifdef svnapot 1 `else 0 `endif )); 
        let ifc();
        mkdtlb#(1, True) _temp(ifc);
        return (ifc);
      endmodule 

      import sa_itlb      :: * ;
      (*synthesize*)
      module mkitlb_instance(Ifc_itlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `vaddr, `satp_mode_size, `paddr, `maxvaddr, `lastppnsize, `vpnsize, `subvpn,  `ifdef svnapot 1 `else 0 `endif )); 
        let ifc();
        mkitlb#(1, True) _temp(ifc);
        return (ifc);
      endmodule 
    `endif 
  `endif
`endif


endpackage: mmu_instance

