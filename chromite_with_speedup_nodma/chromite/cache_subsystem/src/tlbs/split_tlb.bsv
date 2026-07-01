/* 
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: generic tlb for different page size  

--------------------------------------------------------------------------------------------------
*/
package split_tlb; 

`ifdef async_reset
  import RegOverrides  :: *;
`endif
import GetPut       ::*;
import FIFOF        ::*;
import SpecialFIFOs ::*;
import RegFile      ::*;
import Vector       ::*;
import OInt         ::*;
import Assert       ::*;
import ConfigReg    ::*;

import dcache_types	   ::*;
import mmu_types	   ::*;
import replacement_tlb ::*;
`include "mmu.defines"
`include "Logger.bsv" 

/*doc:interface: interface for split tlb*/
interface Ifc_split_tlb#(
						 numeric type min_satp_mode,	//not a compile time macro
             numeric type min_hgatp_mode,
						 numeric type ways,
						 numeric type sets,
		  			 numeric type vpnsize,				//not a compile time macro
						 numeric type page_offset,		//not a compile time macro
             numeric type subvpn,
						 numeric type xlen,
						 numeric type ppnsize,
             numeric type lastppnsize,
						 numeric type vaddr,
						 numeric type paddr,
						 numeric type max_varpages,
						 numeric type asidwidth,
						 numeric type satp_mode_size,
             numeric type svnapot
						);
	/*doc:method: it takes the request from the core which is provided by the sa_tlb */
	method Action ma_request_frm_core (TLB_core_request#(vaddr, asidwidth) req);
	/*doc:method: sends the response back to sa_tlb */
	method ActionValue#(SplitTLB_response#(ppnsize)) mv_response_to_sa_tlb ;
	/*doc:method: makes an entry to tlb using the ptw response */
	method Action ma_tlb_entry_frm_ptw (PTW_response_splitTLB#(vaddr, max_varpages, ppnsize, asidwidth, paddr) resp);
	/* doc:method: tell the core that reset is done */
	method Bool mv_reset_done;
endinterface

function Bit#(m) reSize (Bit#(n) din) provisos( Add#(m,n,mn) );
  Bit#(mn) x = zeroExtend(din);
  return truncate(x);
endfunction:reSize

/* doc:module: implementation of a generic split tlb */
module mk_split_tlb#(parameter Page_size page_size, parameter Bit#(2) alg, parameter String name,
  parameter Bool complex_sfence)
	(Ifc_split_tlb#(min_satp_mode,
                  min_hgatp_mode, 
									ways, 
									sets, 
									vpnsize,    		//not a comiple time macro   
									page_offset, 		//not a comiple time macro
                  subvpn,
									xlen, 
									ppnsize, 
                  lastppnsize,
									vaddr,
									paddr, 
									max_varpages, 
									asidwidth, 
							    satp_mode_size,
                  svnapot))
  	provisos(
  	Log#(TMax#(1,sets),lnsets),
		Add#(a__, TAdd#(vpnsize, page_offset), xlen),
		Add#(b__, TAdd#(vpnsize, page_offset), vaddr),
		Add#(c__, xlen, 64), // xlen should be <= 64
		Add#(xlen, 94, d__),
		Add#(sets, e__, 512), //sets cannot take more than 9 bits else 4kib page will not exist
		Add#(f__, TSub#(page_offset, 12), vaddr),
		Add#(g__, TSub#(page_offset, 12), ppnsize),
		Add#(satp_mode_size, h__, xlen),
		Add#(12, i__, page_offset),
		Add#(j__, ppnsize, xlen), // ppnsize <= xlen
		Add#(satp_mode_size, k__, vaddr),
		Add#(l__, asidwidth, vaddr)
	`ifdef sv32
		,Add#(vpnsize, page_offset, 32)
	`elsif sv39
		,Add#(vpnsize, page_offset, 39)
	`elsif sv48
		,Add#(vpnsize, page_offset, 48)
	`elsif sv57
		,Add#(vpnsize, page_offset, 57)
	`endif		
	);
    
	let v_min_satp_mode  = valueOf(min_satp_mode);
  let v_min_hgatp_mode = valueOf(min_hgatp_mode);
	let v_ways 					 = valueOf(ways);
	let v_sets 					 = valueOf(sets);
	let v_vpnsize 			 = valueOf(vpnsize);
	let v_page_offset 	 = valueOf(page_offset);
  let v_subvpn 	       = valueOf(subvpn);
	let v_xlen 					 = valueOf(xlen);
	let v_max_varpages 	 = valueOf(max_varpages);
	let v_ppnsize 			 = valueOf(ppnsize);
  let v_lastppnsize 	 = valueOf(lastppnsize);
	let v_asidwidth 		 = valueOf(asidwidth);
  let v_svnapot 		   = valueOf(svnapot);
    

	String split_tlb="";

	/*doc:reg: this wire holds input from sa_dtlb */
	Reg#(TLB_core_request#(vaddr, asidwidth)) rg_req <- mkRegA(?);
	/*doc:reg: register to initialize the TLBs to 0 on reset*/
	// Reg#(Bool) rg_initialize <- mkRegA(True); //TODO : remove this
	/*doc:reg: register to index into the TLBs during initialization phase.*/
	Reg#(Bit#(lnsets)) rg_index <- mkRegA(0);
	/*doc:reg: to hold the values related to sfence when sfence is detected */
	Reg#(SfenceReq#(vaddr, asidwidth)) rg_sfence <- mkConfigReg(unpack(0));

	// for using the replacement algorithm 
	Ifc_replace#(sets, ways) replacement <- mkreplace(alg);
	
	/*doc:vector: tlb where each entry is of TLB_entry type */
	Vector#(ways, RegFile#(Bit#(lnsets), TLB_entry#(TSub#(vpnsize, lnsets), ppnsize, asidwidth))) 
	v_tlb <- replicateM(mkRegFileFull);

	/*doc:vector: containing valid state for each tlb entry */
	Vector#(ways, Vector#(sets,Reg#(Bool))) v_tlb_valid <- replicateM(replicateM(mkRegA(False)));

	/*doc:vector: stores the lookup value */
	Vector#(ways, Reg#(TLB_entry#(TSub#(vpnsize, lnsets), ppnsize, asidwidth))) 
	v_rg_lookup <- replicateM(mkRegA(unpack(0)));

	/*doc:function: perform tag match given a virtual page number*/
	function Bit#(ways) fn_tag_match (Bit#(vpnsize) lv_r, Bit#(satp_mode_size) satp, Bit#(asidwidth) asid);
		Bit#(ways) lv_hit= 0;
		// Bit#(satp_mode_size) lv_current_satp_mode = truncateLSB(lv_request.satp);
		Bit#(TSub#(vpnsize, lnsets)) _r = truncateLSB(lv_r);// tag
		for(Integer i= 0 ; i < v_ways; i = i+1)begin
			lv_hit[i] = pack((v_rg_lookup[i].permissions.v) 
        			&& (_r == v_rg_lookup[i].tag) 
      				&& (v_rg_lookup[i].asid == asid || v_rg_lookup[i].permissions.g)
					&& (satp >= fromInteger(v_min_satp_mode)) );
		end
		return lv_hit;
	endfunction : fn_tag_match

	/*doc:function: to extract tag out of virtual address*/
	function Bit#(TSub#(vpnsize, lnsets)) fn_get_tag(Bit#(vaddr) lv_va);
		Bit#(TAdd#(vpnsize, page_offset)) lv_vpn_without_zeroes = truncate(lv_va);
		Bit#(vpnsize) lv_vpn = truncateLSB(lv_vpn_without_zeroes);// removing pageoffset
		Bit#(TSub#(vpnsize, lnsets)) lv_tag = truncateLSB(lv_vpn);
		return lv_tag;
	endfunction:fn_get_tag

	/*doc:function: to get vpn(size vpnsize+offset) out of virtual address*/
	function Bit#(TSub#(TAdd#(vpnsize, page_offset), 12)) fn_get_vpn(Bit#(vaddr) lv_va);
		Bit#(TAdd#(vpnsize, page_offset)) lv_vpn_without_zeroes = truncate(lv_va);
		Bit#(TSub#(TAdd#(vpnsize, page_offset), 12)) lv_vpn = truncateLSB(lv_vpn_without_zeroes);// vpn with 12 offset truncated
		return lv_vpn;
	endfunction: fn_get_vpn
		
	/*doc:function: to get the index given a virtual address*/
	function Bit#(lnsets) fn_get_index(Bit#(vaddr) lv_va);
		Bit#(TAdd#(vpnsize, page_offset)) lv_vpn_without_zeroes = truncate(lv_va); // removing extra zeroes from vpn in the prefix
		Bit#(vpnsize) lv_vpn = truncateLSB(lv_vpn_without_zeroes); // removing the page offset from vpn
		Bit#(lnsets) lv_index = reSize(lv_vpn); // extracting index from vpn'
		return lv_index;
	endfunction:fn_get_index 

	/*doc:rule: This rule fires only when the request recieved from the core has sfence set
		first the rule check that if the particular tlb is configured for simple or complex sfence,
		this is done by checking the parameter passed to the split tlb module at the 
		time of instantiation if it is configured for complex sfence the rs1 and rs2 field are checked,
		below mentioned are a sumarised version of the different condition of rs1 and rs2, else if it configured
		as simple sfence then the valid bits corresponding to all the entries in tlbs are set to FALSE.
		rs1_x0 and rs2_x0 indicates the registers points to x0 register i.e the value is zero .
		
		rs1: indicates virtual address that needs to be flushed in the tlbs
		rs2: indicates the asid that needs to be flushed in the tlbs
		
		 rs1_x0   rs2_x0 	= Iterate and flush all entries (non-conditional flush of the whole tlb)
		!rs1_x0   rs2_x0 	= flush only one entry pointed out by rs1
		 rs1_x0  !rs2_x0 	= iterate and flush entries whose asid matches rs2 or 'G' bit of permissions is set
		!rs1_x0  !rs2_x0  = flush entry, if tag made using rs1 vpn matches the entry tag 
												and for rs2 match the asid field are checked along with the global permission
												
		During sfence operation to flush out a entry, a register containing a valid bit corresponding to each  tlb entry 
		is set to FALSE and at the time of lookup this valid bit and the 'V' bit of the permissions 
		are andded to synchronise the validity of the tlb entry*/ 
	rule rl_sfence(rg_sfence.sfence);
	`ifndef simpl_sfence
	  if (complex_sfence) begin
  	  Bool lv_rs2_x0 = rg_sfence.rs2addr == 0;
		  Bool lv_rs1_x0 = rg_sfence.rs1addr == 0;

		  for (Integer i = 0; i< v_ways; i = i + 1) begin
			  let lv_index = (lv_rs1_x0)?rg_index:fn_get_index(rg_sfence.rs1);
			  let lv_tag   = fn_get_tag(rg_sfence.rs1);
			  let lv_entry = v_tlb[i].sub(lv_index);
			  Bool lv_asid_match = lv_rs2_x0 || (rg_sfence.rs2 == lv_entry.asid && !lv_entry.permissions.g);
			  Bool lv_vpn_match  = lv_rs1_x0 || (lv_tag == lv_entry.tag);
			  if (lv_asid_match && lv_vpn_match && v_sets > 0) begin
				  v_tlb_valid[i][lv_index] <= False;
				  `logLevel( splittlb, 0, $format("%sSplitTLB[",name,fshow(page_size),"]: Sfence Hit"))
			  end
		  end
		  if(lv_rs1_x0) begin
			  if (v_sets > 0 && (valueOf(TExp#(lnsets)) != v_sets) && (rg_index == fromInteger(v_sets-1)))
				  rg_index <= 0;
			  else
				  rg_index <= rg_index + 1;
		  end
		  if(lv_rs1_x0 && lv_rs2_x0)begin
		  `logLevel( splittlb, 0, $format("%sSplitTLB[",name,fshow(page_size),"]: Simple SFencing Now flush all entries"))
		  end 
		  else if (!lv_rs1_x0 && lv_rs2_x0)begin
		  `logLevel( splittlb, 1, $format("%sSplitTLB[",name,fshow(page_size),"]: SFencing Now flush at va:%h",rg_sfence.rs1))
		  end
		  else if (lv_rs1_x0 && !lv_rs2_x0)begin
		  `logLevel( splittlb, 1, $format("%sSplitTLB[",name,fshow(page_size),"]: SFencing Now flush at asid:%h",rg_sfence.rs2))
		  end 
		  else if (!lv_rs1_x0 && !lv_rs2_x0)begin
		  `logLevel( splittlb, 2, $format("%sSplitTLB[",name,fshow(page_size),"]: SFencing Now flush at va:%h asid:%h",rg_sfence.rs1, rg_sfence.rs2))
		  end  

		  rg_sfence.sfence <= (!lv_rs1_x0)? False: !(v_sets > 0 && rg_index == fromInteger(v_sets-1));
	  end else 
	`endif
	  begin
  	  `logLevel( splittlb, 0, $format("%sSplitTLB[",name,fshow(page_size),"]: SFencing the whole TLB"))
		  for (Integer i = 0; i< v_ways; i = i + 1) begin
		  	for (Integer j = 0; j< v_sets; j = j + 1) begin
		  		v_tlb_valid[i][j] <= False;
		  	end
		  end
		  rg_sfence.sfence <= False;
		end
	endrule:rl_sfence

	method Action ma_request_frm_core (TLB_core_request#(vaddr, asidwidth) lv_req)if(!rg_sfence.sfence);
		rg_req <= lv_req;
		`logLevel( splittlb, 0, $format("%sSplitTLB[",name,fshow(page_size),"]: received req: ",fshow(lv_req)))
		if (v_sets > 0) begin
		  let lv_index = fn_get_index(lv_req.address);
		  Vector#(ways, TLB_entry#(TSub#(vpnsize, lnsets), ppnsize, asidwidth)) lv_lookup;
		  for(Integer i= 0 ; i <= valueOf(ways)-1; i= i+1)begin
			  lv_lookup[i] = v_tlb[i].sub(lv_index);
			  lv_lookup[i].permissions.v = v_tlb_valid[i][lv_index] && lv_lookup[i].permissions.v;
		  end
		  writeVReg(v_rg_lookup,lv_lookup);
		  rg_sfence <= lv_req.sfence_req; 
		end
	endmethod:ma_request_frm_core

	method ActionValue#(SplitTLB_response#(ppnsize)) mv_response_to_sa_tlb if(!rg_sfence.sfence);
		// .. This should check for hit, permissions and fault. Generate a miss and move-on otherwise.
		Bit#(TAdd#(vpnsize, page_offset)) _m = truncate(rg_req.address); // remove the extra zero in the front of the vpn 
		Bit#(vpnsize) lv_vpn = truncateLSB(_m); // remove the page_offset
		Bit#(satp_mode_size) satp = truncateLSB(rg_req.satp);
		Bit#(asidwidth) asid = truncate(rg_req.satp >> v_ppnsize);
		Bit#(ways) lv_hit = fn_tag_match(lv_vpn, satp, asid);
		/*`ifdef ASSERT
	    if (v_ways> 0)
    	dynamicAssert(countOnes(lv_hit) <= 1,"TLB: More than one way is a hit in the TLB found");
    `endif*/
		// use one-hot selection mechanism
		TLB_entry#(TSub#(vpnsize, lnsets), ppnsize, asidwidth) lv_hit_entry = unpack(0);
		if (v_sets > 0) begin
		  lv_hit_entry = select(readVReg(v_rg_lookup),unpack(lv_hit));
		  if(v_sets > 0 && |lv_hit == 1) begin
			  `logLevel( splittlb, 2, $format("%sSplitTLB[",name,fshow(page_size),"]: Hit in tlb va:%h hit:%b entry: ",rg_req.address, lv_hit, fshow(lv_hit_entry)))
			end 
		end
		Bit#(TSub#(page_offset, 12)) lower_pa = truncate(rg_req.address >> 12); //part of the vpn of the request will be added
		Bit#(ppnsize) new_ppn = lv_hit_entry.ppn | zeroExtend(lower_pa);
		return(SplitTLB_response{	ppn        : new_ppn,
															permissions: lv_hit_entry.permissions,
															tlb_hit    : unpack(|lv_hit)
														});

	endmethod:mv_response_to_sa_tlb
	
	method Action ma_tlb_entry_frm_ptw (PTW_response_splitTLB#(vaddr, max_varpages, ppnsize, asidwidth, paddr)
	lv_resp)if(!rg_sfence.sfence);
		`logLevel( splittlb, 0, $format("%sSplitTLB[",name,fshow(page_size),"]: Received PTW response: ", fshow(lv_resp)))
		let lv_tag = fn_get_tag(lv_resp.va);
		let lv_index = fn_get_index(lv_resp.va);
		let lv_vpn = fn_get_vpn(lv_resp.va);
		Bit#(TSub#(ppnsize,TSub#(page_offset, 12))) upper_pa = truncateLSB(lv_resp.ppn);
		Bit#(TSub#(page_offset, 12)) lower_pa = 0; //part of the vpn of the request will be added
		Bit#(ppnsize) new_ppn = {upper_pa, lower_pa};
		TLB_entry#(TSub#(vpnsize, lnsets), ppnsize, asidwidth) lv_entry = TLB_entry{tag        : lv_tag,
																																								asid       : lv_resp.asid,
																																								ppn        : new_ppn,
																																								permissions: lv_resp.permissions
																																								};						

		if (!lv_resp.trap) begin
			Bit#(ways) lv_valid_mask = ?;
			for (Integer i = 0; i<v_ways; i = i + 1) begin
				lv_valid_mask[i] = pack(v_tlb_valid[i][lv_index]);
			end
      if (v_sets > 0) begin
        let lv_replaceable_way <- replacement.line_replace(lv_index, lv_valid_mask);
        replacement.update_set(lv_index, lv_replaceable_way);
        v_tlb_valid[lv_replaceable_way][lv_index] <= True;
        v_tlb[lv_replaceable_way].upd(lv_index, lv_entry);
				`logLevel( splittlb, 0, $format("%sSplitTLB[",name,fshow(page_size),"]: Allocating index:%d for Tag:",lv_index, fshow(lv_tag), " with entry: ", fshow(lv_entry)))
      end
		end
	endmethod:ma_tlb_entry_frm_ptw

	method mv_reset_done = True;

endmodule

endpackage

