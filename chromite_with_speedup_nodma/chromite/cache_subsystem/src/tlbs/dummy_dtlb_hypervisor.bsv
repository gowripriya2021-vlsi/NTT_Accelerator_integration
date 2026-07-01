/*
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: dummy tlb for hypervisor
it's an empty tlb which for each translation sends the request to ptwalk
also handels the tranparent translation 
--------------------------------------------------------------------------------------------------
*/
package dummy_dtlb_hypervisor;
  `include "Logger.bsv"
  `include "mmu.defines"
  import FIFO               :: * ;
  import FIFOF              :: * ;
  import SpecialFIFOs       :: * ;
  import Vector             :: * ;
  import mmu_types          :: * ;
  import GetPut             :: * ;
  import ConfigReg          :: * ;

  interface Ifc_dtlb#(
                      numeric type xlen,
                      numeric type max_varpages,
                      numeric type ppnsize,
                      numeric type asidwidth,
                      numeric type vmidwidth, //only for hypervisor
                      numeric type vaddr,
                      numeric type satp_mode_size,
                      numeric type paddr,
                      numeric type maxvaddr,
                      numeric type lastppnsize,
                      numeric type vpnsize,
                      numeric type subvpn,
                      numeric type svnapot                         
                      );
    /*doc:subifc: get the request to ptwalk when there is a miss */                    
    interface Get#(PTWalk_tlb_request#(vaddr)) subifc_get_request_to_ptw;
    /*doc:subifc: allow ptwalk to send there response of the request */
    interface Put#(PTW_response_splitTLB#(vaddr, max_varpages, ppnsize, asidwidth, paddr)) subifc_put_response_frm_ptw;

    /*doc:subifc: allow the core to put the request to tlb for a address transalation */
    interface Put#(TLB_core_request#(vaddr, asidwidth)) subifc_put_request_frm_core;
    /*doc:subifc: allow tlb to send out the response of the request from core to core */
    interface Get#(DTLB_core_response#(paddr)) subifc_get_response_to_core;

    /*doc:method: tell if tlb is available */
    method Bool mv_tlb_available;
  `ifdef perfmonitors
    method Bit#(1) mv_perf_counters;
  `endif
  endinterface 

  module mkdtlb#(parameter Bit#(32) hartid, parameter Bool complex_sfence) (Ifc_dtlb#(xlen, max_varpages, ppnsize, asidwidth, 
          vmidwidth, vaddr, satp_mode_size, paddr, maxvaddr, lastppnsize, vpnsize, subvpn, svnapot))
        provisos(
            Add#(d__, ppnsize, xlen),
            Add#(b__, TMul#(TSub#(max_varpages, 1), subvpn), vaddr),
            Add#(e__, TMul#(TSub#(max_varpages, 1), subvpn), ppnsize),
          `ifdef RV64
            Add#(c__, 1, TSub#(vaddr, maxvaddr)),
            Add#(g__, TAdd#(lastppnsize, TAdd#(TMul#(TSub#(max_varpages, 1), subvpn), 12)), vaddr),
          `else
            Add#(g__, vaddr, TAdd#(lastppnsize, TAdd#(TMul#(TSub#(max_varpages, 1), subvpn), 12))),
          `endif
            Add#(satp_mode_size, i__, xlen),
            Add#(lastppnsize, k__, ppnsize),
            Add#(j__, TMul#(TSub#(max_varpages, 1), subvpn), vpnsize),
            Add#(a__, TLog#(max_varpages), TLog#(TMul#(TSub#(max_varpages, 1), subvpn))),             
            Add#(f__, vpnsize, vaddr),
            Add#(h__, paddr, vaddr),
            Add#(satp_mode_size, l__, vaddr),
            Add#(m__, asidwidth, vaddr)
        );

    let v_xlen				    = valueOf(xlen);
    let v_max_varpages		= valueOf(max_varpages);
    let v_ppnsize			    = valueOf(ppnsize);
    let v_asidwidth			  = valueOf(asidwidth);
    let v_vmidwidth			  = valueOf(vmidwidth);
    let v_vaddr				    = valueOf(vaddr);
    let v_satp_mode_size	= valueOf(satp_mode_size);
    let v_paddr           = valueOf(paddr);
    let v_maxvaddr        = valueOf(maxvaddr);
    let v_lastppnsize     = valueOf(lastppnsize);
    let v_vpnsize         = valueOf(vpnsize);
    let v_subvpn          = valueOf(subvpn);
    let v_svnapot         = valueOf(svnapot);

    Vector#( 1, Reg#(VPNTag#(vpnsize, asidwidth, max_varpages, subvpn, ppnsize))) v_vpn_tag <- replicateM(mkReg(unpack(0))) ;

    /*doc:reg: register to invalidate the entry after use*/
    Reg#(Bool) rg_valid <- mkReg(False);
    Reg#(Trap) rg_trap <- mkReg(unpack(0));

    /*doc:reg: register to indicate which entry need to be filled/replaced*/
    Reg#(Bit#(TLog#(1))) rg_replace <- mkReg(0);
    /*doc:reg: register to store the va of the lookup */
    Reg#(Bit#(vaddr)) rg_miss_queue <- mkReg(0);
    FIFOF#(PTWalk_tlb_request#(vaddr)) ff_request_to_ptw <- mkSizedFIFOF(2);
    FIFOF#(LookUpResult#(VPNTag#(vpnsize, asidwidth, max_varpages, subvpn, ppnsize), vaddr)) ff_lookup_result <- mkSizedFIFOF(2);
    FIFOF#(DTLB_core_response#(paddr)) ff_core_response <- mkBypassFIFOF();

    /*doc:reg: register to indicate that a tlb miss is in progress*/
    Reg#(Bool) rg_tlb_miss <- mkReg(False);

    /*doc:reg: register to indicate the tlb is undergoing an sfence*/
    Reg#(SfenceReq#(vaddr, asidwidth)) rg_sfence <- mkConfigReg(unpack(0));

  `ifdef perfmonitors
    /*doc:wire: */
    Wire#(Bit#(1)) wr_count_misses <- mkDWire(0);
  `endif

    rule rl_sfence(rg_sfence.sfence && !rg_tlb_miss && !ff_lookup_result.notEmpty); 
      rg_sfence.sfence <= False;
      rg_replace <= 0;
      `logLevel( dtlb, 1, $format("DTLB[%2d]: SFencing Now simple sfence",hartid))      
    endrule:rl_sfence

    /*doc:rule: */
    rule rl_send_response(!rg_sfence.sfence);
      let lookup = ff_lookup_result.first;
      ff_lookup_result.deq;
      Bit#(12) page_offset = lookup.va[11 : 0];
      Bit#(vpnsize) fullvpn = truncate(lookup.va >> 12);
      `logLevel( dtlb, 1, $format("DTLB[%2d]: LookupResult: ",hartid,fshow(lookup)))
      if(lookup.translation_done)begin
        ff_core_response.enq(DTLB_core_response{address: truncate(lookup.va),
                                                trap   : lookup.trap,
                                                cause  : lookup.cause,
                                                tlbmiss: False
                                              `ifdef hypervisor   
                                                ,gpa    : ?/*resp.gpa*///cause is access fault not page-fault
                                              `endif });
      end
      else begin
        Bool page_fault = False;
        Bit#(`causesize) cause = lookup.access == 0 ?`Load_pagefault : `Store_pagefault;
        let pte = lookup.pte  ;        
        let permissions = pte.permissions;
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) mask = truncate(pte.pagemask);
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_ppn = truncate(pte.ppn);
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_vpn = truncate(fullvpn);
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_pa  = (mask&lower_ppn)|(~mask&lower_vpn);
        Bit#(lastppnsize) highest_ppn = truncateLSB(pte.ppn);
      `ifdef sv32
        Bit#(vaddr) physicaladdress = truncate({highest_ppn, lower_pa, page_offset});
      `else
        Bit#(vaddr) physicaladdress = zeroExtend({highest_ppn, lower_pa, page_offset});
      `endif

        if(lookup.tlbmiss)begin
          rg_miss_queue <= lookup.va;
          ff_request_to_ptw.enq(PTWalk_tlb_request{address : lookup.va, access : lookup.access,
                                                   priv:lookup.priv, mxr: lookup.mxr, sum:lookup.sum, satp:lookup.satp 
                                                `ifdef hypervisor
                                                  ,v         : lookup.v 
                                                  ,hgatp     : lookup.hgatp
                                                  ,vssatp    : lookup.vssatp
                                                `endif });
          ff_core_response.enq(DTLB_core_response{address  : ?,
                                                  trap     : False,
                                                  cause    : ?,
                                                  tlbmiss  : True
                                                `ifdef hypervisor   
                                                  ,gpa    : ?/*resp.gpa*///no trap so no need for gpa
                                                `endif });
        end
        else begin
          `logLevel( dtlb, 0, $format("DTLB[%2d]: Sending PA:%h Trap:%b",hartid, physicaladdress, rg_trap))
          `logLevel( dtlb, 0, $format("DTLB[%2d]: Hit in TLB:",hartid,fshow(pte)))
          ff_core_response.enq(DTLB_core_response{address  : truncate(physicaladdress),
                                                  trap     : rg_trap.trap,
                                                  cause    : rg_trap.cause,
                                                  tlbmiss  : False
                                                `ifdef hypervisor   
                                                  ,gpa     : ?/*resp.gpa*///need to add gpa as tlb entry
                                                `endif });
        end
      end
    endrule

    interface subifc_put_request_frm_core = interface Put
      method Action put (TLB_core_request#(vaddr, asidwidth) req) if(!rg_sfence.sfence);

        `logLevel( dtlb, 0, $format("DTLB[%2d]: received req: ",hartid,fshow(req)))

        Bit#(12) page_offset = req.address[11 : 0];
        Bit#(vpnsize) fullvpn = truncate(req.address >> 12);
        Bit#(asidwidth) satp_asid = truncate(req.satp >> v_ppnsize);

        /*doc:func: */
        function Bool fn_vtag_match (VPNTag#(vpnsize, asidwidth, max_varpages, subvpn, ppnsize) t);
          return t.permissions.v && (({'1,t.pagemask} & fullvpn) == t.vpn)
                                 && (t.asid == satp_asid || t.permissions.g)
                                 && (rg_valid);
        endfunction
        Bit#(satp_mode_size) vssatp_mode = truncateLSB(req.vssatp); // will contain value from vs csr
        Bit#(satp_mode_size) hgatp_mode = truncateLSB(req.hgatp);

        Bit#(vaddr) va = req.address;
        Bit#(`causesize) cause = req.cause;
        Bool trap = req.ptwalk_trap;
        Bool translation_done = False;        
        Bit#(satp_mode_size) satp_mode = truncateLSB(req.satp);
        let hit_entry = find(fn_vtag_match, readVReg(v_vpn_tag));
        Bool tlbmiss = !isValid(hit_entry);
        VPNTag#(vpnsize, asidwidth, max_varpages, subvpn, ppnsize) pte = fromMaybe(?,hit_entry);
        Bit#(TSub#(vaddr, paddr)) upper_bits = truncateLSB(req.address);
        Bit#(2) priv = req.priv;
        
        if(req.v == 1)
          translation_done = (vssatp_mode == 0 && hgatp_mode == 0)? True: False;
        else 
          translation_done = (satp_mode == 0 || req.priv == 3 || req.ptwalk_req || req.ptwalk_trap)? True: False;
        
        if(!trap && translation_done)begin
           trap = |upper_bits == 1;
           cause = req.access == 0? `Load_access_fault: `Store_access_fault;
        end

        if(req.sfence_req.sfence && !req.ptwalk_req)begin
          rg_sfence <= req.sfence_req;
        end
        else begin
          ff_lookup_result.enq(LookUpResult{va: va, trap: trap, cause: cause,
                                            translation_done: translation_done,
                                            tlbmiss: tlbmiss, pte: pte, access: req.access,
                                            priv:req.priv, mxr: req.mxr, sum:req.sum, satp:req.satp
                                            `ifdef hypervisor
                                              ,v         : req.v 
                                              ,hgatp     : req.hgatp
                                              ,vssatp    : req.vssatp
                                            `endif });
        end

        if(req.sfence_req.sfence)
          rg_tlb_miss <= False;
        else if(rg_tlb_miss && req.ptwalk_trap)
          rg_tlb_miss <= False;
        else if(!translation_done && !req.ptwalk_req) begin
          rg_tlb_miss <= tlbmiss;
        `ifdef perfmonitors
          wr_count_misses <= pack(tlbmiss);
        `endif
        rg_valid <= False;
        end

      endmethod
    endinterface;

    interface subifc_put_response_frm_ptw = interface Put
      method Action put(PTW_response_splitTLB#(vaddr, max_varpages, ppnsize, asidwidth, paddr) resp) if(rg_tlb_miss && !rg_sfence.sfence);
        let core_req = rg_miss_queue ;
        Bit#(12) page_offset = core_req[11 : 0];

        Bit#(vpnsize) fullvpn = truncate(core_req >> 12);
        Bit#(ppnsize) fullppn = resp.ppn;
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) mask = '1;
        Bit#(TLog#(TMul#(TSub#(max_varpages,1),subvpn))) shiftamt;
        if(resp.levels == 0 && resp.n == 1 && v_svnapot == 1)
          shiftamt = 4;// napot bits
        else
          shiftamt = fromInteger(v_subvpn) * zeroExtend(resp.levels);
        mask = mask << shiftamt;
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_ppn = truncate(fullppn);
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_vpn = truncate(core_req >> 12);
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_pa =(mask&lower_ppn)|(~mask&lower_vpn);
        Bit#(lastppnsize) highest_ppn = truncateLSB(fullppn);
      `ifdef sv32
        Bit#(vaddr) physicaladdress = truncate({highest_ppn, lower_pa, page_offset});
      `else
        Bit#(vaddr) physicaladdress = zeroExtend({highest_ppn, lower_pa, page_offset});
      `endif

        VPNTag#(vpnsize, asidwidth, max_varpages, subvpn, ppnsize) tag = VPNTag{permissions: resp.permissions,
                                                                                vpn        : {'1,mask} & fullvpn,
                                                                                asid       : resp.asid,
                                                                                pagemask   : mask,
                                                                                ppn        : fullppn };
        if(!resp.trap) begin 
          `logLevel( dtlb, 0, $format("DTLB[%2d]: Allocating index:%d for Tag:",hartid, rg_replace, fshow(tag)))
          v_vpn_tag[0] <= tag;
			    rg_valid <= True;
          rg_trap <= Trap{trap: resp.trap, cause: resp.cause};
        end

      endmethod
    endinterface;

    interface subifc_get_response_to_core = toGet(ff_core_response);

    interface subifc_get_request_to_ptw = toGet(ff_request_to_ptw);

    method mv_tlb_available = !rg_tlb_miss && ff_lookup_result.notFull;
  
  `ifdef perfmonitors
    method mv_perf_counters = wr_count_misses;
  `endif

  endmodule

endpackage

