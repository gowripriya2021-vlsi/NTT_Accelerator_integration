/*
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: dummy tlb to test hypervisor
it's an empty tlb which for each translation sends the request to ptwalk
also handels the tranparent translation 

--------------------------------------------------------------------------------------------------
*/
package dummy_dtlb_supervisor;
  import Vector::*;
  import FIFOF::*;
  import DReg::*;
  import SpecialFIFOs::*;
  import FIFO::*;
  import GetPut::*;

  import dcache_types::*;
  import mmu_types :: * ;
  `include "mmu.defines"
  `include "Logger.bsv"
  
  

  interface Ifc_dtlb#(
                            numeric type xlen,
                            numeric type max_varpages,
                            numeric type ppnsize,
                            numeric type asidwidth,
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

  module mkdtlb#(parameter Bit#(32) hartid, parameter Bool complex_sfence)(Ifc_dtlb#(xlen, 
                max_varpages, ppnsize, asidwidth, vaddr, satp_mode_size, paddr, maxvaddr, 
                lastppnsize, vpnsize, subvpn, svnapot))
        provisos( Add#(satp_mode_size, a__, vaddr),
                  Add#(b__, paddr, vaddr),
                  Add#(c__, TLog#(max_varpages), TLog#(TMul#(TSub#(max_varpages, 1),subvpn))),
                  Add#(d__, TMul#(TSub#(max_varpages, 1), subvpn), ppnsize),
                  // Add#(e__, TMul#(TSub#(max_varpages, 1), subvpn), paddr),
                  Add#(f__, TAdd#(lastppnsize, TAdd#(TMul#(TSub#(max_varpages, 1), subvpn),12)), xlen),
                  Add#(lastppnsize, g__, ppnsize),
                  Add#(h__, paddr, xlen),
                  Add#(i__, TMul#(TSub#(max_varpages, 1), subvpn), vaddr));
    
    let v_xlen				    = valueOf(xlen);
    let v_max_varpages		= valueOf(max_varpages);
    let v_ppnsize			    = valueOf(ppnsize);
    let v_asidwidth			  = valueOf(asidwidth);
    let v_vaddr				    = valueOf(vaddr);
    let v_satp_mode_size	= valueOf(satp_mode_size);
    let v_paddr           = valueOf(paddr);
    let v_maxvaddr        = valueOf(maxvaddr);
    let v_lastppnsize     = valueOf(lastppnsize);
    let v_vpnsize         = valueOf(vpnsize);
    let v_subvpn          = valueOf(subvpn);
    let v_svnapot         = valueOf(svnapot);

    /*doc:fifo: This fifo holds the request that needs to be sent to the PTW on a miss in the DTLB.
     * This fifo must be atleast 2 entries deep, since its possible that a TLB in ITLB in the
     * previous will cause a PTW to access the DTLB in the current cycle - where the current
     * Load./store instruction hased caused a DTLB Miss. This DTLB Miss must be parked to the
     * processed by the PTW at a later time while addressing the request from the PTW pertaining to
     * the previous cycle ITLB Miss*/
		FIFOF#(PTWalk_tlb_request#(vaddr)) ff_request_to_ptw <- mkSizedFIFOF(2);
		FIFOF#(PTW_response_splitTLB#(vaddr, max_varpages, ppnsize, asidwidth, paddr)) ff_response_frm_ptw <- mkBypassFIFOF();
		FIFOF#(TLB_core_request#(vaddr, asidwidth)) ff_request_frm_core <- mkSizedFIFOF(2);
		FIFOF#(DTLB_core_response#(paddr)) ff_response_to_core <- mkBypassFIFOF();


		function Bit#(xlen) fn_gen_phy_address (Gen_add#(vaddr, ppnsize, max_varpages) g);
      Bit#(TMul#(TSub#(max_varpages,1),subvpn)) mask = '1;
      Bit#(TLog#(TMul#(TSub#(max_varpages,1),subvpn))) shiftamt;
      if(g.levels == 0 && g.n && valueOf(svnapot)==1)
        shiftamt = 4;// napot bits
      else
        shiftamt = fromInteger(v_subvpn) * zeroExtend(g.levels);
      mask = mask << shiftamt;
      Bit#(12) page_offset = g.addr[11:0];//gva or request.address
      Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_ppn = truncate(g.ppn);
      Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_vpn = truncate(g.addr >> 12);
      Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_pa  =(mask&lower_ppn)|(~mask&lower_vpn);
      Bit#(lastppnsize) highest_ppn = truncateLSB(g.ppn);
    `ifdef sv32
      Bit#(xlen) physicaladdress = truncate({highest_ppn, lower_pa, page_offset});
    `else
      Bit#(xlen) physicaladdress = zeroExtend({highest_ppn, lower_pa, page_offset});
    `endif

    return physicaladdress;
    endfunction:fn_gen_phy_address
		
		/*doc:rule: This rule send response back to core.
					First it deq the resquest made by the core then calls a method to get the 
					response from individual tlb of different page size, then it based of priority* selects 
					the tlb response where there is a hit and sends the response back to core with 
					the translation.
					if there is a miss then rule send the request to page-table walk and response back to 
					core indicating its a miss
					or there is tranparent translation
					*priority : this is because it may be case when translation to a virtual address
					is present in multiple tlbs
					from spec: a page is upgraded to a superpage without first clearing the original
					non-leaf PTE's valid bit and executing an SfENCE.VMA with rs1=x0, or if multiple 
					TLBS exist inparallel at a given level of hierarchy*/
		rule rl_transparent_response ;
			let req = ff_request_frm_core.first;			
			Bit#(satp_mode_size) satp_mode = truncateLSB(req.satp);
			Bool transparent_translation ;
			transparent_translation = (satp_mode == 0 || req.priv == 3 || req.ptwalk_req || req.ptwalk_trap);
			if( transparent_translation ) begin
				Bit#(`causesize) cause = req.cause;
        Bool trap = req.ptwalk_trap;
        Bit#(TSub#(vaddr, paddr)) upper_bits = truncateLSB(req.address);
				if(!trap && transparent_translation)begin
           trap = |upper_bits == 1;
           cause = req.access == 0? `Load_access_fault: `Store_access_fault;
        end
				ff_response_to_core.enq(DTLB_core_response{ address : truncate(req.address), // send the va 
																										trap    : trap,				 
																										cause   : cause,
																										tlbmiss : False 
																									});
				
			end
			else begin
				//send the request for a ptwalk        
        ff_request_to_ptw.enq(PTWalk_tlb_request{ address : req.address,
                                                  access  : req.access,
                                                  priv		: req.priv,
                                                  mxr     : req.mxr,
                                                  sum     : req.sum,
                                                  satp    : req.satp 
                                                  
                                                 });
			end
			
		endrule
    
    /*doc:rule: this rule is responsible to get the response back from ptw and send the response to 
								core back after appending the response with correct pageoffset*/
		rule rl_response_frm_ptw;
			let req = ff_request_frm_core.first;
			let resp = ff_response_frm_ptw.first;
			`logLevel( dtlb, 0, $format("[%2d]DTLB : Received response from PTW: ",hartid,fshow(resp)))
			ff_response_frm_ptw.deq;
			ff_request_frm_core.deq;

			let m = Gen_add{addr   : req.address,
											ppn    : resp.ppn, 
											levels : resp.levels,
											n      : unpack(resp.n)};
			let physicaladdress = fn_gen_phy_address(m);
			
			ff_response_to_core.enq(DTLB_core_response{ address : truncate(physicaladdress), // translated address 
																									trap    : resp.trap,				 
																									cause   : resp.cause,
																									tlbmiss : True 
																								});
		endrule

    interface subifc_get_request_to_ptw = toGet(ff_request_to_ptw);
		interface subifc_put_response_frm_ptw = toPut(ff_response_frm_ptw);
		interface subifc_get_response_to_core = toGet(ff_response_to_core);

    interface subifc_put_request_frm_core = interface Put 
			method Action put(TLB_core_request#(vaddr, asidwidth) req) ;
        ff_request_frm_core.enq(req);
				//what to do for sfence operations 
        
				`logLevel( dtlb, 0, $format("[%2d]DTLB : received and sent to PTW req: ",hartid,fshow(req)))
			endmethod

		endinterface;

    method mv_tlb_available = True;
  `ifdef perfmonitors
    // TODO: performance counters
    method mv_perf_counters = ?;
  `endif

	endmodule 


endpackage