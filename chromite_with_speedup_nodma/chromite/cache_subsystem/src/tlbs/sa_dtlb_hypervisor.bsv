/*
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: set associative data tlbs

--------------------------------------------------------------------------------------------------
*/

package sa_dtlb_hypervisor; 
`ifdef async_reset
  import RegOverrides  :: *;
`endif
	import GetPut       			:: * ;
	import FIFOF        			:: * ;
	import SpecialFIFOs 			:: * ;
	import RegFile      			:: * ;
	import Vector       			:: * ;
	import OInt         			:: * ;
	import ConfigReg        	:: * ;
	import resize             :: * ;

	import mmu_types     			  :: * ;
	import split_tlb_hypervisor :: * ;
	import sa_dtlb_instances	  :: * ;
	`include "mmu.defines"
	`include "Logger.bsv"

  interface Ifc_dtlb#(
											numeric type xlen,
											numeric type max_varpages,
											numeric type ppnsize,
											numeric type asidwidth,
											numeric type vmidwidth,
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

		/*doc:subifc: allow the core/ptwalk to put the request to tlb for a address transalation */
		interface Put#(TLB_core_request#(vaddr, asidwidth)) subifc_put_request_frm_core;
		/*doc:subifc: allow tlb to send out the response of the request from core to core */
		interface Get#(DTLB_core_response#(paddr)) subifc_get_response_to_core;

		/*doc:method: tell if tlb is available */
		method Bool mv_tlb_available;
  `ifdef perfmonitors
    method Bit#(1) mv_perf_counters;
  `endif
	endinterface
 
	/*doc:module: implementation of set associative traslation lookaside buffer */
	(*conflict_free="rl_response_frm_ptw, rl_response"*)
	module mkdtlb#(parameter Bit#(32) hartid, parameter Bool complex_sfence) (Ifc_dtlb#(xlen, max_varpages, ppnsize, asidwidth, 
																											 vmidwidth, vaddr, satp_mode_size, paddr, maxvaddr, 
																											 lastppnsize, vpnsize, subvpn, svnapot ))
		provisos(
					`ifdef RV64
						Add#(a__, paddr, 56),
					`else
						Add#(a__, paddr, 34),
					`endif	
						Add#(satp_mode_size, b__, xlen),			
						Add#(c__, xlen, 64),
						Add#(d__, ppnsize, xlen),			
						Add#(e__, ppnsize, vaddr), // ppnsize <= xlen
						Add#(f__, paddr, xlen),
						Add#(0,vaddr,`vaddr),
						Add#(0,paddr,`paddr),
						Add#(0,xlen,`xlen),
						Add#(0,ppnsize,`ppnsize),
						Add#(0,max_varpages,`max_varpages),
						Add#(0,asidwidth,`asidwidth)
						);

    let v_xlen						= valueOf(xlen);
		let v_max_varpages		= valueOf(max_varpages);
		let v_ppnsize					= valueOf(ppnsize);
		let v_asidwidth				= valueOf(asidwidth);
		let v_vaddr						= valueOf(vaddr);
		let v_paddr 					= valueOf(paddr);
		let v_satp_mode_size	= valueOf(satp_mode_size);
		let v_svnapot					= valueOf(svnapot);

		let tlb_4kb <- mkdtlb_4kb(complex_sfence);
	`ifdef svnapot
		let tlb_napot_64kb <- mkdtlb_64kb(complex_sfence);
	`endif 
	`ifdef sv32
		let tlb_4mb <- mkdtlb_4mb(complex_sfence);
	`elsif sv39 
		let tlb_2mb <- mkdtlb_2mb(complex_sfence);
		let tlb_1gb <- mkdtlb_1gb(complex_sfence);
	`elsif sv48
		let tlb_2mb <- mkdtlb_2mb(complex_sfence);
		let tlb_1gb <- mkdtlb_1gb(complex_sfence); 
		let tlb_512gb <- mkdtlb_512gb(complex_sfence);
	`elsif sv57
		let tlb_2mb <- mkdtlb_2mb(complex_sfence);
		let tlb_1gb <- mkdtlb_1gb(complex_sfence);
		let tlb_512gb <- mkdtlb_512gb(complex_sfence);
		let tlb_256tb <- mkdtlb_256tb(complex_sfence);
	`endif
	
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

		/*doc:reg: register to indicate that a tlb miss is in progress*/
		Reg#(Bool) rg_tlb_miss[2] <- mkCReg(2,False);
		
		function Bool fn_select(SplitTLB_responseH#(ppnsize, paddr) lv_x);
		  return lv_x.tlb_hit;
		endfunction

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
		rule rl_response ;
			 
			Vector#(TAdd#(max_varpages,1), SplitTLB_responseH#(ppnsize, paddr)) v_resp;
			let req = ff_request_frm_core.first;
			ff_request_frm_core.deq;
      if (`dtlb_sets_4kb > 0 && `dtlb_ways_4kb > 0)
  			v_resp[0] <- tlb_4kb.mv_response_to_sa_tlb();
  	  else
  		  v_resp[0] = unpack(0);

		`ifdef svnapot
			if (`dtlb_sets_64kb > 0 && `dtlb_ways_64kb > 0 )
				v_resp[1] <- tlb_napot_64kb.mv_response_to_sa_tlb();
			else
				v_resp[1] = unpack(0);
		`else
			v_resp[1] = unpack(0);
		`endif

    `ifdef sv32
			if (`dtlb_sets_4mb > 0 && `dtlb_ways_4mb > 0)
			  v_resp[1] <- tlb_4mb.mv_response_to_sa_tlb();
			else
			  v_resp[1] = unpack(0);

			v_resp[v_max_varpages] = unpack(0);	

  	`elsif sv39		
			if (`dtlb_sets_2mb > 0 && `dtlb_ways_2mb > 0)
			  v_resp[2] <- tlb_2mb.mv_response_to_sa_tlb();
			else
			  v_resp[2] = unpack(0);
      if (`dtlb_sets_1gb > 0 && `dtlb_ways_1gb > 0)
			  v_resp[3] <- tlb_1gb.mv_response_to_sa_tlb();
		  else
		    v_resp[3] = unpack(0);
						
    `elsif sv48		
			if (`dtlb_sets_2mb > 0 && `dtlb_ways_2mb > 0)
			  v_resp[2] <- tlb_2mb.mv_response_to_sa_tlb();
			else
			  v_resp[2] = unpack(0);
      if (`dtlb_sets_1gb > 0 && `dtlb_ways_1gb > 0)
			  v_resp[3] <- tlb_1gb.mv_response_to_sa_tlb();
		  else
		    v_resp[3] = unpack(0);		
      if (`dtlb_sets_512gb > 0 && `dtlb_ways_512gb > 0)
			  v_resp[4] <- tlb_512gb.mv_response_to_sa_tlb();
			else
			  v_resp[4] = unpack(0);
				
		`elsif sv57			
			if (`dtlb_sets_2mb > 0 && `dtlb_ways_2mb > 0)
			  v_resp[2] <- tlb_2mb.mv_response_to_sa_tlb();
			else
			  v_resp[2] = unpack(0);
      if (`dtlb_sets_1gb > 0 && `dtlb_ways_1gb > 0)
			  v_resp[3] <- tlb_1gb.mv_response_to_sa_tlb();
		  else
		    v_resp[3] = unpack(0);	
			if (`dtlb_sets_512gb > 0 && `dtlb_ways_512gb > 0)
			  v_resp[4] <- tlb_512gb.mv_response_to_sa_tlb();
			else
			  v_resp[4] = unpack(0);
      if (`dtlb_sets_256tb > 0 && `dtlb_ways_256tb > 0)
  			v_resp[5] <- tlb_256tb.mv_response_to_sa_tlb();
  	  else
		    v_resp[5] = unpack(0);			
		`endif
			

			/* hit entry is assigned the value of the tlb entry that is a "hit" out of all the tlbs of different page size
			* reverse function is used in selecting the hit as for multiple hits in different tlb preference is
			* given to superpage entry*/
			let hit_entry = find(fn_select, reverse(v_resp));
			/* hit index capture the index of the "hit" entry telling which page the hit corresponds to*/ 
			let hit_index = findIndex(fn_select, reverse(v_resp));
			/* napot_index contains the valid hit_index of the hit entry else if miss then its don't care*/
			let napot_index = fromMaybe(?, hit_index);
			/* resp contains the hit tlb entry if there is miss then it contains don't care*/
			SplitTLB_responseH#(ppnsize, paddr) resp = fromMaybe(?, hit_entry);
			Bool tlbmiss = !isValid(hit_entry); // true if there is a miss else false
			Bit#(12) offset = truncate(req.address);
			/*doc:note: part of the logic below is for tranparent translation, for a translation va is 
									completly equal to pa if not there is trap*/
			Bit#(`causesize) cause = req.cause;
			Bool trap = req.ptwalk_trap;
			Bool translation_done = False;
			Bit#(satp_mode_size) satp_mode   = truncateLSB(req.satp);
			Bit#(satp_mode_size) vssatp_mode = truncateLSB(req.vssatp); // will contain value from vs csr
			Bit#(satp_mode_size) hgatp_mode  = truncateLSB(req.hgatp);
			//checks for transparent translation 
		`ifndef sv32
			Bit#(TSub#(vaddr, paddr)) upper_bits = truncateLSB(req.address);
		`else
			Bit#(1) upper_bits = 0;
		`endif
			
			if(req.v == 1)
				translation_done = (vssatp_mode == 0 && hgatp_mode == 0)? True: False;
			else 
				translation_done = (satp_mode == 0 || req.priv == 3 || req.ptwalk_req || req.ptwalk_trap)? True: False;

			if(!trap && translation_done)begin
					trap = |upper_bits == 1;
					cause = req.access == 0? `Load_access_fault: `Store_access_fault;
			end
			if(translation_done)begin // respond to core with virtual address of the request if there is transparent translation 
				ff_response_to_core.enq(DTLB_core_response{ address : truncate(req.address), // send the va 
																										trap    : trap,				 
																										cause   : cause,
																										tlbmiss : False 
																									`ifdef hypervisor   
																										,gpa    : ?/*resp.gpa*///as this this access_fault
																									`endif });
				`logLevel( dtlb, 0, $format("[%2d]DTLB : Transparent Translation. PhyAddr: %h",hartid,req.address))
			end
			else begin
				rg_tlb_miss[0] <= tlbmiss;				
				if (tlbmiss)begin//if there is a miss 
					ff_request_to_ptw.enq(PTWalk_tlb_request{ address : req.address,
																										access  : req.access,
																										priv		: req.priv,
																										mxr     : req.mxr,
                                                    sum     : req.sum,
                                                    satp    : req.satp 
																									`ifdef hypervisor
																										,v         : req.v 
																										,hgatp     : req.hgatp
																										,vssatp    : req.vssatp
																									`endif	});
					`logLevel( dtlb, 0, $format("[%2d]DTLB : TLBMiss. Sending Address to PTW:%h",hartid,req.address))				
				end

				//check for page fault
				Bool page_fault = False;
				Bool page_fault2 = False;
				AccessTypes access_types = unpack(req.access);				

				//check for page fault only is the set is greater than zero and its a tlb hit
				if(!tlbmiss) begin
					if (req.v == 1)begin 
						// check page fault           
						page_fault2 = fn_fault_check (resp.gpa_permissions, req.sum, req.mxr, req.priv, 
																					access_types, req.v, True );
					end        
					page_fault = fn_fault_check (resp.hpa_permissions, req.sum, req.mxr, req.priv, 
																					access_types, req.v, False );                                
					if(page_fault2)
						cause = req.access == 0 ?`Load_guest_pagefault : `Store_guest_pagefault;
					else 
						cause = req.access == 0 ?`Load_pagefault : `Store_pagefault;
				end 
				/* if there is hit in the napot tlb then ppn corresponding to the tlb entry is changed else 
				* original ppn is passed to the response*/
				Bit#(4) replace_bits = truncate(req.address >> 12);
				Bit#(ppnsize) napot_ppn = {resp.ppn[v_ppnsize -1: 4], replace_bits};
				/* napot bits of the ppn corresponding to the nappot entry is replaced with LSB napot bits of VPN*/ 
				let ppn = (v_svnapot == 1 && napot_index == fromInteger(v_max_varpages -1))? napot_ppn : resp.ppn;
				ff_response_to_core.enq(DTLB_core_response{ address : truncate({ppn,offset}),
																										trap    : page_fault || page_fault2,
																										cause   : cause,
																										tlbmiss : tlbmiss 
																									`ifdef hypervisor   
																										,gpa    : resize(resp.gpa)//need to add gpa as tlb entry
																									`endif });
				if(!tlbmiss)begin// if there is a hit
					`logLevel( dtlb, 0, $format("[%2d]DTLB : Sending PA:%h Trap:%b",hartid,{resp.ppn,offset}, page_fault))
					`logLevel( dtlb, 0, $format("[%2d]DTLB : Hit in TLB:",hartid,fshow(resp))) // can add from which tlb is the hit
				end
			end
			
		endrule:rl_response

		/*doc:rule: this rule is responsible to get the response back from ptw and 
					appen or replace the entry in the concerned tlb*/
		rule rl_response_frm_ptw;
			let resp = ff_response_frm_ptw.first;
			`logLevel( dtlb, 0, $format("[%2d]DTLB : Received response from PTW: ",hartid,fshow(resp)))
			ff_response_frm_ptw.deq;

			let lv_levels = resp.levels;
			if(lv_levels == 0 && `dtlb_sets_4kb > 0 && `dtlb_ways_4kb > 0 && !unpack(resp.n))//4kb
				tlb_4kb.ma_tlb_entry_frm_ptw(resp);
		
		`ifdef svnapot				
			if(lv_levels == 0 && `dtlb_sets_64kb > 0 && `dtlb_ways_64kb > 0 && unpack(resp.n))//NAPOT CACHING
				tlb_napot_64kb.ma_tlb_entry_frm_ptw(resp);
		`endif

		`ifdef sv32
			else if(lv_levels == 1 && `dtlb_sets_4mb > 0 && `dtlb_ways_4mb > 0)//2MB
				tlb_4mb.ma_tlb_entry_frm_ptw(resp);

  	`elsif sv39
			else if(lv_levels == 1 && `dtlb_sets_2mb > 0 && `dtlb_ways_2mb > 0)//2MB
				tlb_2mb.ma_tlb_entry_frm_ptw(resp);
			else if(lv_levels == 2 && `dtlb_sets_1gb > 0 && `dtlb_ways_1gb > 0)//1GB							
				tlb_1gb.ma_tlb_entry_frm_ptw(resp);
					
    `elsif sv48
			else if(lv_levels == 1 && `dtlb_sets_2mb > 0 && `dtlb_ways_2mb > 0)//2MB
				tlb_2mb.ma_tlb_entry_frm_ptw(resp);
			else if(lv_levels == 2 && `dtlb_sets_1gb > 0 && `dtlb_ways_1gb > 0)//1GB							
				tlb_1gb.ma_tlb_entry_frm_ptw(resp);
			else if(lv_levels == 3 && `dtlb_sets_512gb > 0 && `dtlb_ways_512gb > 0)//512 GB
				tlb_512gb.ma_tlb_entry_frm_ptw(resp);
					
		`elsif sv57
			else if(lv_levels == 1 && `dtlb_sets_2mb > 0 && `dtlb_ways_2mb > 0)//2MB
				tlb_2mb.ma_tlb_entry_frm_ptw(resp);
			else if(lv_levels == 2 && `dtlb_sets_1gb > 0 && `dtlb_ways_1gb > 0)//1GB							
				tlb_1gb.ma_tlb_entry_frm_ptw(resp);
			else if(lv_levels == 3 && `dtlb_sets_512gb > 0 && `dtlb_ways_512gb > 0)//512 GB
				tlb_512gb.ma_tlb_entry_frm_ptw(resp);
			else if(lv_levels == 4 && `dtlb_sets_256tb > 0 && `dtlb_ways_256tb > 0)//256 TB
				tlb_256tb.ma_tlb_entry_frm_ptw(resp);
					
		`endif		
		
		endrule
				
		interface subifc_get_request_to_ptw = toGet(ff_request_to_ptw);
		interface subifc_put_response_frm_ptw = toPut(ff_response_frm_ptw);
		interface subifc_get_response_to_core = toGet(ff_response_to_core);

		interface subifc_put_request_frm_core = interface Put 
			method Action put(TLB_core_request#(vaddr, asidwidth) req) ;
				// if the request is sfence enable then request is no enqueued in to the fifo as the core does 
				// not expect a resposne after sending a sfence operation 
        if (req.sfence_req.sfence)
          rg_tlb_miss[1] <= False;
        else if (rg_tlb_miss[1] && !req.ptwalk_req && req.access != 3)
          rg_tlb_miss[1] <= False;
					
        /*doc:note: sfence request is enqued into all the TLBs unconditionally, individual modules of 
				tlb handels the request and flushes the entry based on the metadata and whether the tlb allows
				a simple or complex sfence*/		
				if (!req.sfence_req.sfence) 
					ff_request_frm_core.enq(req);

				if (`dtlb_sets_4kb > 0 && `dtlb_ways_4kb > 0)
  				tlb_4kb.ma_request_frm_core(req);
			
			`ifdef svnapot 			
				if (`dtlb_sets_64kb > 0 && `dtlb_ways_64kb > 0 )
  				tlb_napot_64kb.ma_request_frm_core(req);
			`endif

			`ifdef sv32
				if (`dtlb_sets_4mb > 0 && `dtlb_ways_4mb > 0)
				  tlb_4mb.ma_request_frm_core(req);
			`elsif sv39
				if (`dtlb_sets_2mb > 0 && `dtlb_ways_2mb > 0)
				  tlb_2mb.ma_request_frm_core(req);
				if (`dtlb_sets_1gb > 0 && `dtlb_ways_1gb > 0)
				  tlb_1gb.ma_request_frm_core(req);
					
			`elsif sv48
				if (`dtlb_sets_2mb > 0 && `dtlb_ways_2mb > 0)
				  tlb_2mb.ma_request_frm_core(req);
				if (`dtlb_sets_1gb > 0 && `dtlb_ways_1gb > 0)
				  tlb_1gb.ma_request_frm_core(req);
				if (`dtlb_sets_512gb > 0 && `dtlb_ways_512gb > 0)
					tlb_512gb.ma_request_frm_core(req);	
					
			`elsif sv57
				if (`dtlb_sets_2mb > 0 && `dtlb_ways_2mb > 0)
				  tlb_2mb.ma_request_frm_core(req);
				if (`dtlb_sets_1gb > 0 && `dtlb_ways_1gb > 0)
				  tlb_1gb.ma_request_frm_core(req);
				if (`dtlb_sets_512gb > 0 && `dtlb_ways_512gb > 0)
					tlb_512gb.ma_request_frm_core(req);
				if (`dtlb_sets_256tb > 0 && `dtlb_ways_256tb > 0)
					tlb_256tb.ma_request_frm_core(req);					
			`endif
				`logLevel( dtlb, 0, $format("[%2d]DTLB : received req: ",hartid,fshow(req)))
			endmethod

		endinterface;

    method mv_tlb_available = !rg_tlb_miss[1];
  `ifdef perfmonitors
    // TODO: performance counters
    method mv_perf_counters = ?;
  `endif

	endmodule 
endpackage