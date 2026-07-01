/*
see LICENSE.incore
see LICENSE.iitm

Author : Neel Gala
Email id : neelgala@gmail.com
Details:

--------------------------------------------------------------------------------------------------
*/
package imem;
`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import Vector::*;
  import FIFOF::*;
  import DReg::*;
  import SpecialFIFOs::*;
  import BRAMCore::*;
  import FIFO::*;
  import GetPut::*;
  import Connectable::*;

  import icache_types::*;
  import io_func::*;
  `include "icache.defines"
`ifdef icache
  import icache :: *;
`else
  import null_icache :: *;
`endif
`ifdef supervisor
  import mmu_types :: * ;
  `ifdef hypervisor 
    `ifdef itlb_dummy
      import dummy_itlb_hypervisor ::*;
    `elsif itlb_fa
      import fa_itlb_hypervisor :: * ;
    `elsif itlb_sa
      import sa_itlb_hypervisor :: *;
    `endif 
  `else 
    `ifdef itlb_dummy
      import dummy_itlb_supervisor ::*;
    `elsif itlb_fa
      import fa_itlb :: * ;
    `elsif itlb_sa
      import sa_itlb :: *;
    `endif 
  `endif
`endif

  interface Ifc_imem;
      // -------------------- Cache related interfaces ------------//
    interface Put#(IMem_core_request#(`vaddr, `iesize )) put_core_req;
    interface Get#(IMem_core_response#(`linewidth, `iesize `ifdef hypervisor ,`paddr `endif )) get_core_resp;
    method Action ma_cache_enable(Bool c);
    interface Get#(ICache_mem_readreq#(`paddr)) get_read_mem_req;
    interface Put#(ICache_mem_readresp#(`ibuswidth)) put_read_mem_resp;
  `ifdef icache
    method Bool mv_cache_available;
  `endif
      // ---------------------------------------------------------//
      // - ---------------- TLB interfaces ---------------------- //
  `ifdef supervisor
    interface Get#(PTWalk_tlb_request#(`vaddr)) get_request_to_ptw;
    interface Put#(PTW_response_splitTLB#(`vaddr, `max_varpages, `ppnsize, `asidwidth, `paddr)) put_response_frm_ptw;

  `endif

`ifdef perfmonitors
  `ifdef icache
    method Bit#(5) mv_icache_perf_counters;
  `endif
  `ifdef supervisor
    method Bit#(1) mv_itlb_perf_counters ;
  `endif
`endif
  `ifdef icache_ecc
    method Maybe#(ECC_icache_data#(`paddr, `iways, `iblocks)) mv_ded_data;
    method Maybe#(ECC_icache_data#(`paddr, `iways, `iblocks)) mv_sed_data;
    method Maybe#(ECC_icache_tag#(`paddr, `iways)) mv_ded_tag;
    method Maybe#(ECC_icache_tag#(`paddr, `iways)) mv_sed_tag;
    method Action ma_ram_request(IRamAccess access);
    method Bit#(`respwidth) mv_ram_response;
  `endif
      // ---------------------------------------------------------//
  endinterface

  function ICache_core_request#(`vaddr, `iesize ) get_cache_packet
                                    (IMem_core_request#(`vaddr, `iesize) req);
          return ICache_core_request{ address   : req.address,
                                      fence     : req.fence,
                                      epochs    : req.epochs,
                                      priv      : req.priv};
  endfunction
`ifdef supervisor
  function TLB_core_request#(`vaddr, `asidwidth) get_tlb_packet
                                    (IMem_core_request#(`vaddr, `iesize) req);
          return TLB_core_request{  address     : req.address,
                                    access      : ?,
                                    cause       : ?,
                                    ptwalk_trap : ?,
                                    ptwalk_req  : ?,
                                    sfence_req  : req.sfence_req,
                                    priv        : req.priv
                                    ,mxr        : req.mxr 
                                    ,sum        : req.sum 
                                    ,satp       : req.satp
                                  `ifdef hypervisor
                                     ,v         : req.v 
                                     ,hgatp     : req.hgatp
                                     ,vssatp    : req.vssatp
                                  `endif
                                    };
  endfunction
`endif

  (*synthesize*)
  module mkimem#(parameter Bit#(32) id
    `ifdef pmp ,
        Vector#(`pmpentries, Bit#(8)) pmp_cfg , 
        Vector#(`pmpentries, Bit#(`paddr )) pmp_addr 
    `endif
    `ifdef supervisor
      ,parameter Bool complex_sfence
    `endif
    )(Ifc_imem);
    let icache <- mkicache(id `ifdef pmp ,pmp_cfg, pmp_addr `endif );
  `ifdef supervisor
    Ifc_itlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `ifdef hypervisor `vmidwidth, `endif `vaddr, `satp_mode_size, `paddr, 
              `maxvaddr, `lastppnsize, `vpnsize, `subvpn,  `ifdef svnapot 1 `else 0 `endif ) itlb <-
              mkitlb(id, complex_sfence);
    mkConnection(itlb.subifc_get_response_to_core, icache.put_pa_from_tlb);
  `endif
    interface put_core_req = interface Put
      method Action put (IMem_core_request#(`vaddr, `iesize ) r);
      `ifdef supervisor
        if(!r.sfence_req.sfence)
            icache.put_core_req.put(get_cache_packet(r));
        if(!r.fence)
            itlb.subifc_put_request_frm_core.put(get_tlb_packet(r));
      `else
        icache.put_core_req.put(get_cache_packet(r));
      `endif
      endmethod
    endinterface;
    interface get_core_resp = icache.get_core_resp;
    interface get_read_mem_req = icache.get_read_mem_req;
    interface put_read_mem_resp = icache.put_read_mem_resp;
    method ma_cache_enable =  icache.ma_cache_enable;
  `ifdef icache
    method mv_cache_available    =icache.mv_cache_available ;
  `endif

`ifdef supervisor
    interface get_request_to_ptw = itlb.subifc_get_request_to_ptw;
    interface put_response_frm_ptw = itlb.subifc_put_response_frm_ptw;
`endif
`ifdef perfmonitors
  `ifdef icache
    method mv_icache_perf_counters = icache.mv_perf_counters;
  `endif
  `ifdef supervisor
    method mv_itlb_perf_counters = itlb.mv_perf_counters;
  `endif
`endif
  `ifdef icache_ecc
    method mv_ded_data = icache.mv_ded_data;
    method mv_sed_data = icache.mv_sed_data;
    method mv_ded_tag = icache.mv_ded_tag;
    method mv_sed_tag = icache.mv_sed_tag;
    method ma_ram_request = icache.ma_ram_request;
    method mv_ram_response = icache.mv_ram_response;
  `endif
  endmodule
endpackage

