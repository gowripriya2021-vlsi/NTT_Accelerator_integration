/*
see LICENSE.incore
see LICENSE.iitm

Author : Neel Gala
Email id : neelgala@gmail.com
Details:

--------------------------------------------------------------------------------------------------
*/
package dmem;
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

  import dcache_types::*;
  import io_func::*;
  `include "dcache.defines"
`ifdef dcache
  `ifdef dcache_2rw
    import dcache2rw :: *;
  `elsif dcache_1r1w
    import dcache1r1w :: *;
  `else
    import dcache1rw :: *;
  `endif
`else
  import null_dcache :: *;
`endif
`ifdef supervisor
  import mmu_types :: * ;
  `ifdef hypervisor 
    `ifdef dtlb_dummy
      import dummy_dtlb_hypervisor ::*;
    `elsif dtlb_fa
      import fa_dtlb_hypervisor :: * ;
    `elsif dtlb_sa
      import sa_dtlb_hypervisor :: *;
    `endif 
  `else 
    `ifdef dtlb_dummy
      import dummy_dtlb_supervisor ::*;
    `elsif dtlb_fa
      import fa_dtlb :: * ;
    `elsif dtlb_sa
      import sa_dtlb :: *;
    `endif 
  `endif
`endif

  interface Ifc_dmem;
      // -------------------- Cache related interfaces ------------//
    interface Put#(DMem_request#(`vaddr, TMul#( `dwords, 8),`desize )) receive_core_req;
    interface Get#(DMem_core_response#(TMul#(`dwords, 8), `desize `ifdef hypervisor ,`paddr `endif  )) send_core_cache_resp;
    method Maybe#(DMem_core_response#(TMul#(`dwords,8),`desize `ifdef hypervisor ,`paddr `endif )) send_core_io_resp;

    interface Get#(DCache_io_req#(`paddr, `dbuswidth)) send_mem_io_req;
    interface Put#(DCache_io_response#(`dbuswidth)) receive_mem_io_resp;

    method Action ma_commit_io(Bit#(`desize) currepoch);
    (*always_ready*)
    method Bool mv_dmem_available;

  `ifdef dcache
    method DCache_mem_writereq#(`paddr, TMul#(`dblocks, TMul#(`dwords, 8))) send_mem_wr_req;
    interface Put#(DCache_mem_writeresp) receive_mem_wr_resp;
    method Action deq_mem_wr_req;

    interface Get#(DCache_mem_readreq#(`paddr)) send_mem_rd_req;
    interface Put#(DCache_mem_readresp#(`dbuswidth)) receive_mem_rd_resp;

    /*doc:method: method to recieve the current privilege mode of operation*/
    method Action ma_commit_store(Tuple2#(Bit#(`desize), Bit#(TLog#(`dsbsize))) storecommit);
    method Action ma_cache_enable(Bool c);
    (*always_ready*)
    method Bool mv_storebuffer_empty;
  `endif
      // ---------------------------------------------------------//
      // - ---------------- TLB interfaces ---------------------- //
  `ifdef supervisor
    interface Get#(DMem_core_response#(TMul#(`dwords, 8), `desize `ifdef hypervisor ,`paddr `endif )) get_ptw_resp;
    interface Get#(PTWalk_tlb_request#(`vaddr)) get_req_to_ptw;
    interface Put#(PTW_response_splitTLB#(`vaddr, `max_varpages, `ppnsize, `asidwidth, `paddr)) put_resp_from_ptw;
    interface Get#(DCache_core_request#(`vaddr, TMul#(`dwords, 8), `desize)) get_hold_req;
  `endif
`ifdef perfmonitors
  `ifdef dcache
    method Bit#(13) mv_dcache_perf_counters;
  `endif
  `ifdef supervisor
    method Bit#(1) mv_dtlb_perf_counters ;
  `endif
`endif
  `ifdef dcache_ecc
    method Maybe#(ECC_dcache_data#(`paddr, `dways, `dblocks)) mv_ded_data;
    method Maybe#(ECC_dcache_data#(`paddr, `dways, `dblocks)) mv_sed_data;
    method Maybe#(ECC_dcache_tag#(`paddr, `dways)) mv_ded_tag;
    method Maybe#(ECC_dcache_tag#(`paddr, `dways)) mv_sed_tag;
    method Action ma_ram_request(DRamAccess access);
    method Bit#(`respwidth) mv_ram_response;
`endif
      // ---------------------------------------------------------//
  endinterface

  function DCache_core_request#(`vaddr, TMul#(`dwords,8), `desize ) get_cache_packet
                                    (DMem_request#(`vaddr, TMul#(`dwords, 8), `desize) req);
          return DCache_core_request{ address   : req.address,
                                      fence     : req.fence,
                                      epochs    : req.epochs,
                                      access    : req.access,
                                      size      : req.size,
                                      data      : req.writedata,
                                      priv      : req.priv
                                    `ifdef atomic
                                      ,atomic_op : req.atomic_op
                                    `endif
                                    `ifdef supervisor
                                      ,ptwalk_req: req.ptwalk_req
                                    `endif };
  endfunction
`ifdef supervisor
  function TLB_core_request#(`vaddr, `asidwidth) get_tlb_packet
                                    (DMem_request#(`vaddr, TMul#(`dwords, 8), `desize) req);
          return TLB_core_request{  address     : req.address,
                                    access      : `ifdef atomic (req.access==2 && req.atomic_op=='b0101)? 0: `endif req.access,
                                    cause       : truncate(req.writedata),
                                    ptwalk_trap : req.ptwalk_trap,
                                    ptwalk_req  : req.ptwalk_req,
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
  module mkdmem#(parameter Bit#(32) id
    `ifdef pmp ,
        Vector#(`pmpentries, Bit#(8)) pmp_cfg, 
        Vector#(`pmpentries, Bit#(`paddr)) pmp_addr 
    `endif
    `ifdef supervisor
      ,parameter Bool complex_sfence
    `endif
    )(Ifc_dmem);

    let dcache <- mkdcache(id `ifdef pmp ,pmp_cfg, pmp_addr `endif );
  `ifdef supervisor
    Ifc_dtlb#(`xlen, `max_varpages, `ppnsize, `asidwidth, `ifdef hypervisor `vmidwidth, `endif `vaddr, `satp_mode_size, `paddr, 
              `maxvaddr, `lastppnsize, `vpnsize, `subvpn, `ifdef svnapot 1 `else 0 `endif ) dtlb <-
              mkdtlb(id, complex_sfence);
    mkConnection(dtlb.subifc_get_response_to_core, dcache.put_pa_from_tlb);
  `endif
    interface receive_core_req = interface Put
      method Action put (DMem_request#(`vaddr, TMul#( `dwords, 8),`desize ) r);
      `ifdef supervisor
        if(r.ptwalk_req || !r.sfence_req.sfence)
            dcache.receive_core_req.put(get_cache_packet(r));
        if(!r.fence)
            dtlb.subifc_put_request_frm_core.put(get_tlb_packet(r));
      `else
        dcache.receive_core_req.put(get_cache_packet(r));
      `endif
      endmethod
    endinterface;
    interface send_core_cache_resp = dcache.send_core_cache_resp;
    method send_core_io_resp = dcache.send_core_io_resp;
    interface send_mem_io_req = dcache.send_mem_io_req;
    interface receive_mem_io_resp = dcache.receive_mem_io_resp;
    method ma_cache_enable =  dcache.ma_cache_enable;
`ifdef dcache
    method send_mem_wr_req = dcache.send_mem_wr_req;
    interface receive_mem_wr_resp = dcache.receive_mem_wr_resp;
    interface send_mem_rd_req = dcache.send_mem_rd_req;
    interface receive_mem_rd_resp = dcache.receive_mem_rd_resp;
    method deq_mem_wr_req = dcache.deq_mem_wr_req;
`endif
    method ma_commit_store = dcache.ma_commit_store;
    method ma_commit_io = dcache.ma_commit_io;
    method mv_dmem_available    =dcache.mv_cache_available `ifdef supervisor && dtlb.mv_tlb_available `endif ;
    method mv_storebuffer_empty  =dcache.mv_storebuffer_empty;
  `ifdef supervisor
    interface get_ptw_resp = dcache.get_ptw_resp;
    interface get_req_to_ptw = dtlb.subifc_get_request_to_ptw;
    interface put_resp_from_ptw = dtlb.subifc_put_response_frm_ptw;
    interface get_hold_req = dcache.get_hold_req;
  `endif
`ifdef perfmonitors
  `ifdef dcache
    method mv_dcache_perf_counters = dcache.mv_perf_counters;
  `endif
  `ifdef supervisor
    method mv_dtlb_perf_counters = dtlb.mv_perf_counters;
  `endif
`endif
  `ifdef dcache_ecc
    method mv_ded_data = dcache.mv_ded_data;
    method mv_sed_data = dcache.mv_sed_data;
    method mv_ded_tag = dcache.mv_ded_tag;
    method mv_sed_tag = dcache.mv_sed_tag;
    method ma_ram_request = dcache.ma_ram_request;
    method mv_ram_response = dcache.mv_ram_response;
`endif
  endmodule
endpackage

