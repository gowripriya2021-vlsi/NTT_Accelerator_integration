/*
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: fully associative instruction tlbs does not support sv32 for now

--------------------------------------------------------------------------------------------------
*/

package sa_itlb; 
`ifdef async_reset
  import RegOverrides  :: *;
`endif
import GetPut       		:: * ;
import FIFOF        		:: * ;
import SpecialFIFOs 		:: * ;
import RegFile      		:: * ;
import Vector       		:: * ;
import OInt         		:: * ;

import mmu_types     		:: * ;
import split_tlb     		:: * ;
import sa_itlb_instances	:: * ;

`include "mmu.defines"
`include "Logger.bsv"

interface Ifc_itlb#(
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
    interface Get#(ITLB_core_response#(paddr)) subifc_get_response_to_core;

  `ifdef perfmonitors
    method Bit#(1) mv_perf_counters;
  `endif
endinterface

module mkitlb#(parameter Bit#(32) hartid, parameter Bool complex_sfence) (Ifc_itlb#(xlen, max_varpages, ppnsize, asidwidth, 
                                                    vaddr, satp_mode_size, paddr, maxvaddr, 
                                                    lastppnsize, vpnsize, subvpn, svnapot ))
    provisos(
           `ifdef RV64
            Add#(a__, paddr, 56),            
            Add#(b__, TAdd#(lastppnsize, TAdd#(TMul#(TSub#(max_varpages,1), subvpn), 12)), vaddr),
          `else
            Add#(a__, paddr, 34),            
            Add#(b__, vaddr, TAdd#(lastppnsize, TAdd#(TMul#(TSub#(max_varpages,1), subvpn), 12))),
          `endif 
            Add#(satp_mode_size, c__, xlen),
            Add#(d__, paddr, vaddr),// vaddr and paddr relationship
            Add#(lastppnsize, e__, ppnsize),// ppnsize and lastppnsize relationship 
            Add#(f__, TLog#(max_varpages), TLog#(TMul#(TSub#(max_varpages,1), subvpn))),// for line 323
            Add#(g__, TMul#(TSub#(max_varpages,1), subvpn), ppnsize),
            Add#(h__, TMul#(TSub#(max_varpages,1), subvpn), vaddr),
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
    let v_paddr           = valueOf(paddr);
    let v_satp_mode_size	= valueOf(satp_mode_size);
    let v_subvpn          = valueOf(subvpn);
    let v_lastppnsize     = valueOf(lastppnsize);
    let v_svnapot					= valueOf(svnapot);

    let tlb_4kb <- mkitlb_4kb(complex_sfence);
`ifdef svnapot
    let tlb_napot_64kb <- mkitlb_64kb(complex_sfence);
`endif     
`ifdef sv32
    let tlb_4mb <- mkitlb_4mb(complex_sfence);
`elsif sv39 
    let tlb_2mb <- mkitlb_2mb(complex_sfence);
    let tlb_1gb <- mkitlb_1gb(complex_sfence);
`elsif sv48
    let tlb_2mb <- mkitlb_2mb(complex_sfence);
    let tlb_1gb <- mkitlb_1gb(complex_sfence); 
    let tlb_512gb <- mkitlb_512gb(complex_sfence);
`elsif sv57
    let tlb_2mb <- mkitlb_2mb(complex_sfence);
    let tlb_1gb <- mkitlb_1gb(complex_sfence);
    let tlb_512gb <- mkitlb_512gb(complex_sfence);
    let tlb_256tb <- mkitlb_256tb(complex_sfence);
`endif 
    

    FIFOF#(PTWalk_tlb_request#(vaddr)) ff_request_to_ptw <- mkSizedFIFOF(2);
    FIFOF#(PTW_response_splitTLB#(vaddr, max_varpages, ppnsize, asidwidth, paddr)) ff_response_frm_ptw <- mkBypassFIFOF();
    FIFOF#(TLB_core_request#(vaddr, asidwidth)) ff_request_frm_core <- mkSizedFIFOF(2);
    FIFOF#(ITLB_core_response#(paddr)) ff_response_to_core <- mkBypassFIFOF();

    /*doc:reg: when set to true this register indicates that the ITLB has faced a missed and is
     * waiting for the PTW to respond with either a fault or a valid PTE. This register is CReg
     * because as soon a TLB miss is detected, no new requests should be taken in the same cycle by
     * the IMEM system. This is important to avoid the I$ from latching a new request to the SRAMS.
    */
    Reg#(Bool) rg_tlb_miss[2] <- mkCRegA(2,False);

    function Bool fn_select(SplitTLB_response#(ppnsize) lv_x);
        return lv_x.tlb_hit;
    endfunction
    
    /*doc:rule: This rule send response back to core.
                First it deq the resquest made by the core then calls a method to get the 
                response from individual tlb of different page size, then it based of priority* selects 
                the tlb response where there is a hit and sends the response back to core with 
                the translation.
                if there is a miss then rule send the request to page-table walk with proper access defined
                or it can be a transparent translation 
                *priority : this is because it may be case when translation to a virtual address
                is present in multiple tlbs
                from spec: a page is upgraded to a superpage without first clearing the original
                non-leaf PTE's valid bit and executing an SfENCE.VMA with rs1=x0, or if multiple 
                TLBS exist inparallel at a given level of hierarchy*/
    rule rl_response if(!rg_tlb_miss[0]); 
        `logLevel( itlb, 0, $format("[%2d]ITLB : inside response rl",hartid))

        Vector#(TAdd#(max_varpages,1), SplitTLB_response#(ppnsize)) v_resp;
        let req = ff_request_frm_core.first;
        ff_request_frm_core.deq;

        if (`itlb_sets_4kb > 0 && `itlb_ways_4kb > 0)
					v_resp[0] <- tlb_4kb.mv_response_to_sa_tlb();
        else
					v_resp[0] = unpack(0);

			`ifdef svnapot
				if (`itlb_sets_64kb > 0 && `itlb_ways_64kb > 0 )
					v_resp[1] <- tlb_napot_64kb.mv_response_to_sa_tlb();
				else
					v_resp[1] = unpack(0);
			`else
				v_resp[1] = unpack(0);
			`endif

			`ifdef sv32
				if (`itlb_sets_4mb > 0 && `itlb_ways_4mb > 0)
					v_resp[1] <- tlb_4mb.mv_response_to_sa_tlb();
				else
					v_resp[1] = unpack(0);

				v_resp[v_max_varpages] = unpack(0);	

			`elsif sv39		
				if (`itlb_sets_2mb > 0 && `itlb_ways_2mb > 0)
					v_resp[2] <- tlb_2mb.mv_response_to_sa_tlb();
				else
					v_resp[2] = unpack(0);
				if (`itlb_sets_1gb > 0 && `itlb_ways_1gb > 0)
					v_resp[3] <- tlb_1gb.mv_response_to_sa_tlb();
				else
					v_resp[3] = unpack(0);
							
			`elsif sv48		
				if (`itlb_sets_2mb > 0 && `itlb_ways_2mb > 0)
					v_resp[2] <- tlb_2mb.mv_response_to_sa_tlb();
				else
					v_resp[2] = unpack(0);
				if (`itlb_sets_1gb > 0 && `itlb_ways_1gb > 0)
					v_resp[3] <- tlb_1gb.mv_response_to_sa_tlb();
				else
					v_resp[3] = unpack(0);		
				if (`itlb_sets_512gb > 0 && `itlb_ways_512gb > 0)
					v_resp[4] <- tlb_512gb.mv_response_to_sa_tlb();
				else
					v_resp[4] = unpack(0);
					
			`elsif sv57			
				if (`itlb_sets_2mb > 0 && `itlb_ways_2mb > 0)
					v_resp[2] <- tlb_2mb.mv_response_to_sa_tlb();
				else
					v_resp[2] = unpack(0);
				if (`itlb_sets_1gb > 0 && `itlb_ways_1gb > 0)
					v_resp[3] <- tlb_1gb.mv_response_to_sa_tlb();
				else
					v_resp[3] = unpack(0);	
				if (`itlb_sets_512gb > 0 && `itlb_ways_512gb > 0)
					v_resp[4] <- tlb_512gb.mv_response_to_sa_tlb();
				else
					v_resp[4] = unpack(0);
				if (`itlb_sets_256tb > 0 && `itlb_ways_256tb > 0)
					v_resp[5] <- tlb_256tb.mv_response_to_sa_tlb();
				else
					v_resp[5] = unpack(0);			
			`endif
        

        let hit_entry = find(fn_select, reverse(v_resp));
        let hit_index = findIndex(fn_select, reverse(v_resp));
        let napot_index = fromMaybe(?, hit_index);
        SplitTLB_response#(ppnsize) resp = fromMaybe(?, hit_entry);
        Bool tlbmiss = !isValid(hit_entry);
        let permissions = resp.permissions;
        Bool page_fault = False;
        Bit#(12) offset = truncate(req.address);
        // transparent translation
        Bit#(satp_mode_size) satp_mode = truncateLSB(req.satp);
        if(satp_mode == 0 || req.priv == 3)begin
            Bit#(paddr) coreresp = truncate(req.address);
        `ifndef sv32
            Bit#(TSub#(vaddr, paddr)) upper_bits = truncateLSB(req.address);
        `else
            Bit#(1) upper_bits = 0;
        `endif
            Bool trap = |upper_bits == 1;
            ff_response_to_core.enq(ITLB_core_response{ address  : truncate(coreresp),
                                                        trap     : trap,
                                                        cause    : `Inst_access_fault
                                                      `ifdef hypervisor   
                                                        ,gpa    : ? // as this fault is different
                                                      `endif });
            `logLevel( itlb, 0, $format("[%2d]ITLB : Transparent Translation. PhyAddr: %h",hartid,coreresp))
        end
        else if(!tlbmiss)begin // if there is a hit
            // check for permission faults different from dtlb
        /* `ifndef sv32
            if(unused_va != signExtend(req.address[`maxvaddr-1]))begin
              page_fault = True;
            end
          `endif*/
            // pte.x == 0
            if(!permissions.x)
              page_fault = True;
            // pte.a == 0
            else if(!permissions.a)
              page_fault = True;
            // pte.u == 0 for user mode
            else if(!permissions.u && req.priv == 0)
              page_fault = True;
            // pte.u = 1 for supervisor
            else if(permissions.u && req.priv == 1)
              page_fault = True;
            
            Bit#(4) replace_bits = truncate(req.address >> 12);
            Bit#(ppnsize) napot_ppn = {resp.ppn[v_ppnsize -1: 4], replace_bits};
            let ppn = (v_svnapot == 1 && napot_index == fromInteger(v_max_varpages -1))? napot_ppn : resp.ppn; 
                              
            ff_response_to_core.enq(ITLB_core_response{ address : truncate({ppn,offset}),
                                                        trap    : page_fault,
                                                        cause   : `Inst_pagefault
                                                      `ifdef hypervisor   
                                                        ,gpa    : ?/*resp.gpa*///need to add gpa as tlb entry
                                                      `endif });
            `logLevel( itlb, 0, $format("[%2d]ITLB : Sending PA:%h Trap:%b",hartid, {resp.ppn,offset}, page_fault))
		    `logLevel( itlb, 0, $format("[%2d]ITLB : Hit in TLB:",hartid,fshow(resp))) // can add from which tlb is the hit
        end
        else begin// if there is miss
            // Send virtual - address and indicate it is an instruction access to the PTW
          ff_request_to_ptw.enq(PTWalk_tlb_request{address  : req.address,
                                                    access  : 3,
                                                    priv    : req.priv,
                                                    mxr     : req.mxr,
                                                    sum     : req.sum,
                                                    satp    : req.satp 
                                                  `ifdef hypervisor
                                                    ,v         : req.v 
                                                    ,hgatp     : req.hgatp
                                                    ,vssatp    : req.vssatp
                                                  `endif }); 
          rg_tlb_miss[0] <= True;
        `logLevel( itlb, 0, $format("[%2d]ITLB : TLBMiss. Sending Address to PTW:%h",hartid,req.address))	 
        end 
        
    endrule:rl_response
		
    /*doc:rule: this rule is responsible to get the response back from ptw and 
                append/replace the entry in the concerned tlb*/
    rule rl_response_frm_ptw if (rg_tlb_miss[1]);
        let resp = ff_response_frm_ptw.first;
        ff_response_frm_ptw.deq;
        rg_tlb_miss[1]<= False;

        let lv_levels = resp.levels;
        if(lv_levels == 0 && `itlb_sets_4kb > 0 && `itlb_ways_4kb > 0  && !unpack(resp.n))//4kb
            tlb_4kb.ma_tlb_entry_frm_ptw(resp);   
		
			`ifdef svnapot				
				if(lv_levels == 0 && `itlb_sets_64kb > 0 && `itlb_ways_64kb > 0 && unpack(resp.n))//NAPOT CACHING
					tlb_napot_64kb.ma_tlb_entry_frm_ptw(resp);
			`endif

			`ifdef sv32
				else if(lv_levels == 1 && `itlb_sets_4mb > 0 && `itlb_ways_4mb > 0)//2MB
					tlb_4mb.ma_tlb_entry_frm_ptw(resp);

			`elsif sv39
				else if(lv_levels == 1 && `itlb_sets_2mb > 0 && `itlb_ways_2mb > 0)//2MB
					tlb_2mb.ma_tlb_entry_frm_ptw(resp);
				else if(lv_levels == 2 && `itlb_sets_1gb > 0 && `itlb_ways_1gb > 0)//1GB							
					tlb_1gb.ma_tlb_entry_frm_ptw(resp);
						
			`elsif sv48
				else if(lv_levels == 1 && `itlb_sets_2mb > 0 && `itlb_ways_2mb > 0)//2MB
					tlb_2mb.ma_tlb_entry_frm_ptw(resp);
				else if(lv_levels == 2 && `itlb_sets_1gb > 0 && `itlb_ways_1gb > 0)//1GB							
					tlb_1gb.ma_tlb_entry_frm_ptw(resp);
				else if(lv_levels == 3 && `itlb_sets_512gb > 0 && `itlb_ways_512gb > 0)//512 GB
					tlb_512gb.ma_tlb_entry_frm_ptw(resp);
						
			`elsif sv57
				else if(lv_levels == 1 && `itlb_sets_2mb > 0 && `itlb_ways_2mb > 0)//2MB
					tlb_2mb.ma_tlb_entry_frm_ptw(resp);
				else if(lv_levels == 2 && `itlb_sets_1gb > 0 && `itlb_ways_1gb > 0)//1GB							
					tlb_1gb.ma_tlb_entry_frm_ptw(resp);
				else if(lv_levels == 3 && `itlb_sets_512gb > 0 && `itlb_ways_512gb > 0)//512 GB
					tlb_512gb.ma_tlb_entry_frm_ptw(resp);
				else if(lv_levels == 4 && `itlb_sets_256tb > 0 && `itlb_ways_256tb > 0)//256 TB
					tlb_256tb.ma_tlb_entry_frm_ptw(resp);						
			`endif		

        /*doc:note: in itlb the ptwalk response is also responsible to send the response
                    back to core
                    resp.ppn cannot be directly used as the inclusion of vpn based on the 
                    level is done at split tlb so the ppn in resp.ppn is without taking in consideration 
                    of vpn*/
        Bit#(12) page_offset = resp.va[11 : 0];
        Bit#(ppnsize) fullppn = resp.ppn;
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) mask = '1;
        Bit#(TLog#(TMul#(TSub#(max_varpages,1),subvpn))) shiftamt;
        if(resp.levels == 0 && resp.n == 1 && v_svnapot == 1)
          shiftamt = 4;// napot bits
        else
          shiftamt = fromInteger(v_subvpn) * zeroExtend(resp.levels);
        mask = mask << shiftamt;
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_ppn = truncate(fullppn);
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_vpn = truncate(resp.va >> 12);
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_pa =(mask&lower_ppn)|(~mask&lower_vpn);
        Bit#(lastppnsize) highest_ppn = truncateLSB(fullppn);
      `ifdef sv32
        Bit#(vaddr) physicaladdress = truncate({highest_ppn, lower_pa, page_offset});
      `else
        Bit#(vaddr) physicaladdress = zeroExtend({highest_ppn, lower_pa, page_offset});
      `endif        
		ff_response_to_core.enq(ITLB_core_response{ address : truncate(physicaladdress),
                                                    trap    : resp.trap,
                                                    cause   : resp.cause
                                                  `ifdef hypervisor   
                                                    ,gpa    : resp.gpa
                                                  `endif });
        `logLevel( itlb, 0, $format("[%2d]ITLB : Sending (rl_ptw) PA:%h Trap:%b",hartid, physicaladdress, resp.trap))
    endrule

    interface subifc_get_request_to_ptw = toGet(ff_request_to_ptw);
    interface subifc_put_response_frm_ptw = toPut(ff_response_frm_ptw);
    interface subifc_get_response_to_core = toGet(ff_response_to_core);

    interface subifc_put_request_frm_core = interface Put 
			method Action put(TLB_core_request#(vaddr, asidwidth) req) if (!rg_tlb_miss[1]);
				// if the request is sfence enable then request is no enqueued in to the fifo as the core does 
				// not expect a resposne after sending a sfence operation 
				if (!req.sfence_req.sfence) 
					ff_request_frm_core.enq(req);
				else
						rg_tlb_miss[1] <= False;
				/*doc:note: sfence request is enqued into all the TLBs unconditionally, individual modules of 
				tlb handels the request and flushes the entry based on the metadata and whether the tlb allows
				a simple or complex sfence*/		
				if (`itlb_sets_4kb > 0 && `itlb_ways_4kb > 0)
					tlb_4kb.ma_request_frm_core(req);
			
			`ifdef svnapot 			
				if (`itlb_sets_64kb > 0 && `itlb_ways_64kb > 0 )
					tlb_napot_64kb.ma_request_frm_core(req);
			`endif

			`ifdef sv32
				if (`itlb_sets_4mb > 0 && `itlb_ways_4mb > 0)
					tlb_4mb.ma_request_frm_core(req);
			`elsif sv39
				if (`itlb_sets_2mb > 0 && `itlb_ways_2mb > 0)
					tlb_2mb.ma_request_frm_core(req);
				if (`itlb_sets_1gb > 0 && `itlb_ways_1gb > 0)
					tlb_1gb.ma_request_frm_core(req);
					
			`elsif sv48
				if (`itlb_sets_2mb > 0 && `itlb_ways_2mb > 0)
					tlb_2mb.ma_request_frm_core(req);
				if (`itlb_sets_1gb > 0 && `itlb_ways_1gb > 0)
					tlb_1gb.ma_request_frm_core(req);
				if (`itlb_sets_512gb > 0 && `itlb_ways_512gb > 0)
					tlb_512gb.ma_request_frm_core(req);	
					
			`elsif sv57
				if (`itlb_sets_2mb > 0 && `itlb_ways_2mb > 0)
					tlb_2mb.ma_request_frm_core(req);
				if (`itlb_sets_1gb > 0 && `itlb_ways_1gb > 0)
					tlb_1gb.ma_request_frm_core(req);
				if (`itlb_sets_512gb > 0 && `itlb_ways_512gb > 0)
					tlb_512gb.ma_request_frm_core(req);
				if (`itlb_sets_256tb > 0 && `itlb_ways_256tb > 0)
					tlb_256tb.ma_request_frm_core(req);					
			`endif
				`logLevel( itlb, 0, $format("[%2d]ITLB : received req: ",hartid,fshow(req)))
			endmethod
    endinterface;

  `ifdef perfmonitors
    // TODO: drive performance counters
    method mv_perf_counters = ?;
  `endif
  
endmodule

endpackage
