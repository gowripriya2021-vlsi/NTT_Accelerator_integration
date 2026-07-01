/*
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: dummy tlb to test hypervisor
its an empty tlb which for each translation sends the request to ptwalk
also handels the tranparent translation 

--------------------------------------------------------------------------------------------------
*/
package dummy_itlb_hypervisor;
  import Vector          ::*;
  import FIFOF           ::*;
  import DReg            ::*;
  import SpecialFIFOs    ::*;
  import FIFO            ::*;
  import GetPut          ::*;
  import ConfigReg       ::* ;

  import dcache_types    ::*;
  import mmu_types       ::* ;
  `include "mmu.defines"
  `include "Logger.bsv"
  
  

  interface Ifc_itlb#(
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

    /*doc:subifc: allow the core to put the request to tlb for a address transalation */
    interface Put#(TLB_core_request#(vaddr, asidwidth)) subifc_put_request_frm_core;
    /*doc:subifc: allow tlb to send out the response of the request from core to core */
    interface Get#(ITLB_core_response#(paddr)) subifc_get_response_to_core;

  `ifdef perfmonitors
    method Bit#(1) mv_perf_counters;
  `endif
  endinterface 

  module mkitlb#(parameter Bit#(32) hartid, parameter Bool complex_sfence)(Ifc_itlb#(xlen, 
                max_varpages, ppnsize, asidwidth, vmidwidth, vaddr, satp_mode_size, paddr, maxvaddr, 
                lastppnsize, vpnsize, subvpn, svnapot))
        provisos(Add#(lastppnsize, b__, ppnsize),
                Add#(c__, paddr, xlen),
                Add#(d__, TMul#(TSub#(max_varpages, 1), subvpn), ppnsize),
                // Add#(e__, TMul#(TSub#(max_varpages, 1), subvpn), paddr),
                Add#(f__, TAdd#(lastppnsize, TAdd#(TMul#(TSub#(max_varpages, 1), subvpn),12)), xlen),
                Add#(g__, paddr, vaddr),
                Add#(satp_mode_size, h__, vaddr),
                Add#(i__, TLog#(max_varpages), TLog#(TMul#(TSub#(max_varpages, 1),subvpn))),
                Add#(j__, TMul#(TSub#(max_varpages, 1), subvpn), vaddr)
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

    /*doc:fifo: */
		FIFOF#(PTWalk_tlb_request#(vaddr)) ff_request_to_ptw <- mkSizedFIFOF(1);
		FIFOF#(PTW_response_splitTLB#(vaddr, max_varpages, ppnsize, asidwidth, paddr)) ff_response_frm_ptw <- mkBypassFIFOF();
		FIFOF#(TLB_core_request#(vaddr, asidwidth)) ff_request_frm_core <- mkSizedFIFOF(1);
		FIFOF#(ITLB_core_response#(paddr)) ff_response_to_core <- mkBypassFIFOF();

    /*doc:reg: register to indicate that a tlb miss is in progress*/
    Reg#(Bool) rg_tlb_miss[2] <- mkCRegA(2,False);

    Reg#(TLB_core_request#(vaddr, asidwidth)) core_req <- mkReg(unpack(0));

    /*doc:reg: register to indicate the tlb is undergoing an sfence*/
    Reg#(SfenceReq#(vaddr, asidwidth)) rg_sfence <- mkConfigReg(unpack(0));

  `ifdef perfmonitors
    /*doc:wire: */
    Wire#(Bit#(1)) wr_count_misses <- mkDWire(0);
  `endif

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
		
		rule rl_sfence(rg_sfence.sfence );
      rg_sfence.sfence <= False;
    endrule:rl_sfence

		rule rl_transparent_response if(!rg_sfence.sfence && !rg_tlb_miss[0]);
			let req = ff_request_frm_core.first;
      ff_request_frm_core.deq;		
			Bit#(satp_mode_size) satp_mode = truncateLSB(req.satp);
			Bit#(satp_mode_size) vssatp_mode = truncateLSB(req.vssatp); // will contain value from vs csr
			Bit#(satp_mode_size) hgatp_mode = truncateLSB(req.hgatp);
			Bool transparent_translation ;
			
      if(req.v == 1)
        transparent_translation = (vssatp_mode == 0 && hgatp_mode == 0)? True: False;
			else 
				transparent_translation = (satp_mode == 0 || req.priv == 3)? True: False;
			
			

			//first check for transparent translation is present or not if yes then what kind
			//for vssatp_mode == 0 and hgatp_mode == 0
			if( transparent_translation ) begin
				//TODO:check here probably wrong
				`logLevel( itlb, 0, $format("[%2d]ITLB: Transparent Translation",hartid))
				Bit#(`causesize) cause = req.cause;
        Bit#(TSub#(vaddr, paddr)) upper_bits = truncateLSB(req.address);
				Bool trap = |upper_bits == 1;
				ff_response_to_core.enq(ITLB_core_response{ address : truncate(req.address), // send the va 
																										trap    : trap,				 
																										cause   : `Inst_access_fault
																									`ifdef hypervisor   
																										,gpa    : ?/*resp.gpa*///as this this access_fault
																									`endif });
				
			end
			else begin
				`logLevel( itlb, 0, $format("[%2d]ITLB: Miss. Sending Request to PTW",hartid))
        rg_tlb_miss[0] <= True;
        core_req <= req;
				//send the request for a ptwalk        
        ff_request_to_ptw.enq(PTWalk_tlb_request{ address : req.address,
                                                  access  : 3,
                                                  priv		: req.priv,
                                                  mxr     : req.mxr,
                                                  sum     : req.sum,
                                                  satp    : req.satp 
                                                  ,v      : req.v
                                                  ,hgatp  : req.hgatp
																									,vssatp	: req.vssatp
                                                 });
			end
			
		endrule
    
    /*doc:rule: this rule is responsible to get the response back from ptw and send the response to 
								core back after appending the response with correct pageoffset*/
		rule rl_response_frm_ptw if(rg_tlb_miss[1] && !rg_sfence.sfence);
			let req = core_req;
			let resp = ff_response_frm_ptw.first;
			`logLevel( itlb, 0, $format("[%2d]ITLB : Received response from PTW: ",hartid,fshow(resp)))
			ff_response_frm_ptw.deq;
      rg_tlb_miss[1] <= False;

			Bit#(satp_mode_size) satp_mode = truncateLSB(req.satp);
			Bit#(satp_mode_size) vssatp_mode = truncateLSB(req.vssatp); // will contain value from vs csr
			Bit#(satp_mode_size) hgatp_mode = truncateLSB(req.hgatp);
      Bit#(vaddr) _temp_addr;
      Bit#(TLog#(max_varpages)) _temp_levels;


			if(req.v == 1)begin
				_temp_addr   = ((vssatp_mode != 0 && hgatp_mode != 0) || (vssatp_mode == 0 && hgatp_mode != 0))? zeroExtend(resp.gpa):
												   (vssatp_mode != 0 && hgatp_mode == 0)? resp.gva:0;
				_temp_levels = ((vssatp_mode != 0 && hgatp_mode != 0) || (vssatp_mode == 0 && hgatp_mode != 0))? resp.levels_G:
													 (vssatp_mode != 0 && hgatp_mode == 0)? resp.levels:0;								 
								
			end
			else begin 
				_temp_addr 	 = req.address;
				_temp_levels = resp.levels;
			end 
			let m = Gen_add{addr   : _temp_addr,
											ppn    : resp.ppn, /// change this for hypervisor
											levels : _temp_levels,
											n      : unpack(resp.n)};
			let physicaladdress = fn_gen_phy_address(m);
			
			ff_response_to_core.enq(ITLB_core_response{ address : truncate(physicaladdress), // translated address 
																									trap    : resp.trap,				 
																									cause   : resp.cause
																									,gpa    : resp.gpa
																								});      
      
		endrule

    interface subifc_get_request_to_ptw = toGet(ff_request_to_ptw);
		interface subifc_put_response_frm_ptw = toPut(ff_response_frm_ptw);
		interface subifc_get_response_to_core = toGet(ff_response_to_core);

    interface subifc_put_request_frm_core = interface Put 
			method Action put(TLB_core_request#(vaddr, asidwidth) req) if(!rg_sfence.sfence && !rg_tlb_miss[1]) ;
        if (!req.sfence_req.sfence) 
					ff_request_frm_core.enq(req);
        else
						rg_tlb_miss[1] <= False;
				//what to do for sfence operations :waste a cycle and restart taking the request
        if(req.sfence_req.sfence && !req.ptwalk_req)begin
          rg_sfence <= req.sfence_req;
        end          
        
				`logLevel( itlb, 0, $format("[%2d]ITLB : received : ",hartid,fshow(req)))
			endmethod

		endinterface;

  `ifdef perfmonitors
    // TODO: performance counters
    method mv_perf_counters = ?;
  `endif

	endmodule 


endpackage
