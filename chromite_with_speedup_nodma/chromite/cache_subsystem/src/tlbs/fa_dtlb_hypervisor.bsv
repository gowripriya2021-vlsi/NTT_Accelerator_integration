/*
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: fully associative data tlbs for hypervisor

--------------------------------------------------------------------------------------------------
*/
package fa_dtlb_hypervisor;
	`include "Logger.bsv"
	`include "mmu.defines"
`ifdef async_reset
	import RegOverrides :: *;
`endif
	import FIFO		:: *;
	import FIFOF	:: *;
	import SpecialFIFOs	::*;
	import Vector		::*;
	import mmu_types	::*;
	import GetPut		::*;
	import ConfigReg	::*;

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
            Add#(m__, asidwidth, vaddr),
            Add#(n__, vmidwidth, vaddr)
        );

    let v_xlen			      = valueOf(xlen);
    let v_max_varpages	  = valueOf(max_varpages);
    let v_ppnsize		      = valueOf(ppnsize);
    let v_asidwidth		    = valueOf(asidwidth);
    let v_vmidwidth		    = valueOf(vmidwidth);
    let v_vaddr			      = valueOf(vaddr);
    let v_satp_mode_size  = valueOf(satp_mode_size);
    let v_paddr           = valueOf(paddr);
    let v_maxvaddr        = valueOf(maxvaddr);
    let v_lastppnsize     = valueOf(lastppnsize);
    let v_vpnsize         = valueOf(vpnsize);
    let v_subvpn          = valueOf(subvpn);
    let v_svnapot         = valueOf(svnapot);

	  Vector#( `dtlbsize, Reg#(VPNTagH#(vpnsize, paddr, asidwidth, vmidwidth, ppnsize, max_varpages, subvpn))) v_vpn_tag <- replicateM(mkReg(unpack(0))); 
    
	  /*doc:reg: register to indicate which entry need to be filled/replaced*/
    Reg#(Bit#(TLog#(`dtlbsize))) rg_replace <- mkReg(0);
    /*doc:reg: register to store the va of the lookup */
    Reg#(Bit#(vaddr)) rg_miss_queue <- mkReg(0);
    Reg#(Bit#(1)) rg_miss_v <- mkReg(?);
    FIFOF#(PTWalk_tlb_request#(vaddr)) ff_request_to_ptw <- mkSizedFIFOF(2);
    FIFOF#(LookUpResult#(VPNTagH#(vpnsize, paddr, asidwidth, vmidwidth, ppnsize, max_varpages, subvpn), vaddr)) ff_lookup_result <- mkSizedFIFOF(2);
    FIFOF#(DTLB_core_response#(paddr)) ff_core_response <- mkBypassFIFOF();

    /*doc:reg: register to indicate that a tlb miss is in progress*/
    Reg#(Bool) rg_tlb_miss <- mkReg(False);

    /*doc:reg: register to indicate the tlb is undergoing an sfence*/
    Reg#(SfenceReq#(vaddr, asidwidth)) rg_sfence <- mkConfigReg(unpack(0));

  `ifdef perfmonitors
    /*doc:wire: */
    Wire#(Bit#(1)) wr_count_misses <- mkDWire(0);
  `endif

    function Bool fn_fault_check (TLB_permissions permissions, Bit#(1) sum, Bit#(1) mxr, Bit#(2) lv_priv,  
                                  AccessTypes lv_access_types, Bit#(1) v, Bool s1 );
      Bool page_fault = False;
      /* from spec: if the requested memory access is allowed by the pte.r, pte.w, pte.x, and 
      *  pte.u bits, given the current privilege mode and the value of the SUM and MXR fields of 
      *  the mstatus register. If not, stop and raise a page-fault exception */
      Bool _c = (permissions.u) ? ((lv_priv == 'b01) && (lv_access_types == Fetch|| !unpack(sum))) : (lv_priv != 'b01);
      Bool _d = lv_access_types == Fetch ? !(permissions.x) :
                lv_access_types == Load  ? !(permissions.r) && !(unpack(mxr) && (permissions.x)) :
                                            !((permissions.r) && (permissions.w));
      
      /* form spec: When a virtual page is accessed and the A bit is clear, or is written and 
      *  the D bit is clear, a page-fault exception is raised.*/
      if (!permissions.a ||
          ((lv_access_types == Store || lv_access_types == Atomic) && !permissions.d)) begin 
        page_fault = True;
        // `logLevel( splittlb, 2, $format("DTLB[%d]: Fault Reason - A|D bits not set va:%h",hartid, fullvpn))
      end

      // if not readable and not mxr
      if (_d) begin
        page_fault=True;
        // `logLevel( splittlb, 2, $format("DTLB[%d]: Fault Reason - Access permissions failed va:%h",hartid, fullvpn))
      end

      // supervisor accessing user
      if ( ((v==0) || s1) && _c ) begin
        page_fault=True;
        // `logLevel( splittlb, 2, $format("DTLB[%d]: Fault Reason - User permissions Failed va:%h",hartid, fullvpn))
      end

      return page_fault;
    endfunction 
    
    /*doc:rule: This is the version1 of tlb hypervisor, so here we just clear all the 
		* entries inside of TLB */

    rule rl_sfence(rg_sfence.sfence && !rg_tlb_miss && !ff_lookup_result.notEmpty);
      for (Integer i = 0; i < `dtlbsize; i = i + 1) begin
          v_vpn_tag[i] <= unpack(0);
        end
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
        Bool page_fault2 = False;
        AccessTypes lv_access_types = unpack(lookup.access);
        Bit#(2) lv_priv = lookup.priv;
        Bit#(`causesize) cause ;
        let pte = lookup.pte  ;        
        // let permissions = pte.permissions;
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) mask = truncate(pte.pagemask);
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_ppn = truncate(pte.ppn);
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_vpn = truncate(fullvpn);
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_pa  = (mask&lower_ppn)|(~mask&lower_vpn);
        Bit#(lastppnsize) highest_ppn = truncateLSB(pte.ppn);
      `ifdef sv32
        Bit#(vaddr) physicaladdress = truncate({highest_ppn, lower_pa, page_offset});
      `else
        //TODO:generate hypervisor physical address
        Bit#(vaddr) physicaladdress = zeroExtend({highest_ppn, lower_pa, page_offset});
      `endif

        `logLevel( dtlb, 2, $format("DTLB[%2d]: mask:%h",hartid,mask))
        `logLevel( dtlb, 2, $format("DTLB[%2d]: lower_ppn:%h",hartid,lower_ppn))
        `logLevel( dtlb, 2, $format("DTLB[%2d]: lower_vpn:%h",hartid,lower_vpn))
        `logLevel( dtlb, 2, $format("DTLB[%2d]: lower_pa:%h",hartid,lower_pa))
        `logLevel( dtlb, 2, $format("DTLB[%2d]: highest_ppn:%h",hartid,highest_ppn))

      `ifndef sv32
        Bit#(TSub#(vaddr, maxvaddr)) unused_va = lookup.va[v_vaddr - 1 : v_maxvaddr];
        if(unused_va != signExtend(lookup.va[v_maxvaddr-1]))begin
          page_fault = True;
        end
      `endif
      //first decide wheather it is v=0 | v=1
        //if v=0 permission check only on hpa.permissons/GPA.permissions
        //if v=1 
          //permission check on gpa.permission 
          //permission check on hpa.permission 
          //if fault = True (due to gpa or HPA)
            // if both fault cause is due to gpa 
            // if hpa fault cause is due to hpa
            // if gpa fault cause is due to gpa
          //no fault then send response
        if (lookup.v == 1)begin 
          // check page fault           
          page_fault2 = fn_fault_check (pte.gpa_permissions, lookup.sum, lookup.mxr, lv_priv, 
                                        lv_access_types, lookup.v, True );
        end        
        page_fault = fn_fault_check (pte.hpa_permissions, lookup.sum, lookup.mxr, lv_priv, 
                                        lv_access_types, lookup.v, False );                                
        if(page_fault2)
          cause = lookup.access == 0 ?`Load_guest_pagefault : `Store_guest_pagefault;
        else 
          cause = lookup.access == 0 ?`Load_pagefault : `Store_pagefault;
        
        if(lookup.tlbmiss)begin
          rg_miss_queue <= lookup.va;
          rg_miss_v <= lookup.v;
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
                                                  ,gpa    : ?//no trap so no need for gpa
                                                `endif });
        end
        else begin
          `logLevel( dtlb, 0, $format("DTLB[%2d]: Sending PA:%h Trap:%b",hartid, physicaladdress, page_fault))
          `logLevel( dtlb, 0, $format("DTLB[%2d]: Hit in TLB:",hartid,fshow(pte)))
          ff_core_response.enq(DTLB_core_response{address  : truncate(physicaladdress),
                                                  trap     : page_fault || page_fault2,
                                                  cause    : cause,
                                                  tlbmiss  : False
                                                `ifdef hypervisor   
                                                  ,gpa     : pte.gpa//need for mtval2 if the cause is guest page fault
                                                `endif });
        end
      end
    endrule

    interface subifc_put_request_frm_core = interface Put
      method Action put (TLB_core_request#(vaddr, asidwidth) req) if(!rg_sfence.sfence);

        `logLevel( dtlb, 0, $format("DTLB[%2d]: received req: ",hartid,fshow(req)))

        Bit#(12) page_offset = req.address[11 : 0];//virtual address page offset
        Bit#(vpnsize) fullvpn = truncate(req.address >> 12);//virtual address without page offset
        //for V=0 its ssatp.asid and for V=1 its vssatp.asid
        Bit#(asidwidth) satp_asid = (req.v == 0)? truncate(req.satp >> v_ppnsize) : truncate(req.vssatp >> v_ppnsize);
        //for V=0 its ssatp.asid and for V=1 its hgatp.vmid
        Bit#(vmidwidth) hgatp_vmid = (req.v == 1)? truncate(req.hgatp >> v_ppnsize) : 0 ;


        /*doc:func: tag matching function */
        function Bool fn_vtag_match (VPNTagH#(vpnsize, paddr, asidwidth, vmidwidth, ppnsize, max_varpages, subvpn)t) ;
          return t.gpa_permissions.v && t.hpa_permissions.v 
              && (({'1,t.pagemask} & fullvpn) == t.vpn)
              && (t.v == req.v)
              && ((t.v == 1 && t.vmid == hgatp_vmid) || (t.v==0 && t.vmid ==0))
              && ((t.v==1 && t.asid == satp_asid) || (t.v == 0 && (t.asid == satp_asid || t.hpa_permissions.g)) );

        endfunction
        Bit#(satp_mode_size) satp_mode = truncateLSB(req.satp);
        Bit#(satp_mode_size) vssatp_mode = truncateLSB(req.vssatp); // will contain value from vs csr
        Bit#(satp_mode_size) hgatp_mode = truncateLSB(req.hgatp);

        Bit#(vaddr) va = req.address;
        Bit#(`causesize) cause = req.cause;
        Bool trap = req.ptwalk_trap;
        Bool translation_done ;        
        
        let hit_entry = find(fn_vtag_match, readVReg(v_vpn_tag));
        Bool tlbmiss = !isValid(hit_entry);
        VPNTagH#(vpnsize, paddr, asidwidth, vmidwidth, ppnsize, max_varpages, subvpn) pte = fromMaybe(?,hit_entry);
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
        end

      endmethod
    endinterface;

    interface subifc_put_response_frm_ptw = interface Put
      method Action put(PTW_response_splitTLB#(vaddr, max_varpages, ppnsize, asidwidth, paddr) resp) if(rg_tlb_miss && !rg_sfence.sfence);
        let core_req = rg_miss_queue ;
        let v = rg_miss_v;
        Bit#(12) page_offset = core_req[11 : 0];

        Bit#(asidwidth) satp_asid = (v == 0)? truncate(resp.asid) : truncate(resp.vssatp >> v_ppnsize);
        //for V=0 its ssatp.asid and for V=1 its hgatp.vmid
        Bit#(vmidwidth) hgatp_vmid = (v == 1)? truncate(resp.hgatp >> v_ppnsize) : 0 ;

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
        VPNTagH#(vpnsize, paddr, asidwidth, vmidwidth, ppnsize, max_varpages, subvpn) tag =        VPNTagH{vpn              : {'1,mask} & fullvpn,
                                                                                                gpa              : resp.gpa,
                                                                                                gpa_permissions  : resp.gpa_perm,
                                                                                                hpa              : resp.hpa,
                                                                                                ppn              : fullppn,
                                                                                                hpa_permissions  : resp.hpa_perm,
                                                                                                vmid             : hgatp_vmid,
                                                                                                asid             : satp_asid,
                                                                                                pagemask         : mask,
                                                                                                v                : v
                                                                                                };
        if(!resp.trap) begin
          `logLevel( dtlb, 0, $format("DTLB[%2d]: Allocating index:%d for Tag:",hartid, rg_replace, fshow(tag)))
          v_vpn_tag[rg_replace] <= tag;
			    if ((valueOf(TExp#(TLog#(`dtlbsize))) != valueOf(`dtlbsize)) && (rg_replace == fromInteger(`dtlbsize-1)))
			      rg_replace <= 0;
			    else
            rg_replace <= rg_replace + 1;
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
