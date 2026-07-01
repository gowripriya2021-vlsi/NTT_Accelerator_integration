/* 
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: fully associative itlbs 

--------------------------------------------------------------------------------------------------
*/
package fa_itlb_hypervisor;
  `include "Logger.bsv"
  `include "mmu.defines"
`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import FIFO         :: * ;
  import FIFOF        :: * ;
  import SpecialFIFOs :: * ;
  import Vector       :: * ;
  import mmu_types    :: * ;
  import GetPut       :: * ;
  import ConfigReg    :: * ;

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

    interface Get#(PTWalk_tlb_request#(vaddr)) subifc_get_request_to_ptw;
    interface Put#(PTW_response_splitTLB#(vaddr, max_varpages, ppnsize, asidwidth, paddr)) subifc_put_response_frm_ptw;

    interface Put#(TLB_core_request#(vaddr, asidwidth)) subifc_put_request_frm_core;
    interface Get#(ITLB_core_response#(paddr)) subifc_get_response_to_core;

  `ifdef perfmonitors
    method Bit#(1) mv_perf_counters;
  `endif
  endinterface

  /*doc:module: */
  // (*synthesize*)
  module mkitlb#(parameter Bit#(32) hartid, parameter Bool complex_sfence) (Ifc_itlb#(xlen, max_varpages, ppnsize, asidwidth, 
                                                      vmidwidth, vaddr, satp_mode_size, paddr, maxvaddr,
                                                      lastppnsize, vpnsize, subvpn, svnapot))
    provisos(
        Add#(a__, vpnsize, vaddr),
        Add#(b__, paddr, vaddr),
        Add#(c__, TMul#(TSub#(max_varpages, 1), subvpn), ppnsize),
        Add#(d__, paddr, 64),
        Add#(e__, ppnsize, xlen),
        Add#(f__, TMul#(TSub#(max_varpages, 1), subvpn), vpnsize),        
      `ifdef RV64
        Add#(g__, 1, TSub#(vaddr, maxvaddr)),
        Add#(h__, TAdd#(lastppnsize, TAdd#(TMul#(TSub#(max_varpages, 1), subvpn), 12)), vaddr),
      `else
        Add#(h__, vaddr, TAdd#(lastppnsize, TAdd#(TMul#(TSub#(max_varpages, 1), subvpn), 12))),
      `endif 
        Add#(satp_mode_size, i__, xlen),
        Add#(j__, TMul#(TSub#(max_varpages, 1), subvpn), vaddr),
        Add#(lastppnsize, k__, ppnsize),
        Add#(l__, TLog#(max_varpages), TLog#(TMul#(TSub#(max_varpages, 1),subvpn))),
        Add#(m__, asidwidth, vaddr),
        Add#(satp_mode_size, n__, vaddr),
        Add#(o__, vmidwidth, vaddr)
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

    Vector#( `itlbsize , Reg#(VPNTagH#(vpnsize, paddr, asidwidth, vmidwidth, ppnsize, max_varpages, subvpn)) ) v_vpn_tag <- replicateM(mkReg(unpack(0))) ;

    /*doc:reg: register to indicate which entry need to be filled/replaced*/
    Reg#(Bit#(TLog#(`itlbsize))) rg_replace <- mkReg(0);
    Reg#(Bit#(vaddr)) rg_miss_queue <- mkReg(0);
    Reg#(Bit#(1)) rg_miss_v <- mkReg(?);
    FIFOF#(PTWalk_tlb_request#(vaddr)) ff_request_to_ptw <- mkSizedFIFOF(2);
    FIFOF#(ITLB_core_response#(paddr)) ff_core_respone <- mkSizedFIFOF(2);
    /*doc:reg: register to indicate that a tlb miss is in progress*/
    Reg#(Bool) rg_tlb_miss <- mkReg(False);

    /*doc:reg: register to indicate the tlb is undergoing an sfence*/
    Reg#(SfenceReq#(vaddr, asidwidth)) rg_sfence <- mkConfigReg(unpack(0));

    Wire#(Bit#(xlen)) wr_mstatus <- mkWire();  
  `ifdef perfmonitors
    /*doc:wire: */
    Wire#(Bit#(1)) wr_count_misses <- mkDWire(0);
  `endif

    function Bool fn_fault_check (TLB_permissions permissions, Bit#(2) lv_priv, Bit#(1) v, Bool s1 );
      Bool page_fault = False;
      // check for permission faults
      // `ifndef sv32
      //   Bit#(TSub#(vaddr, maxvaddr)) unused_va = req.address[v_vaddr - 1 : v_maxvaddr];
      //   if(unused_va != signExtend(req.address[v_maxvaddr-1]))begin
      //     page_fault = True;
      //   end
      // `endif
        // pte.x == 0: as all fetch should have execute permission so this check remains
        // same for hyperisor as well as supervisor
        if(!permissions.x)
          page_fault = True;
        // pte.a == 0: 
        else if(!permissions.a)
          page_fault = True;
        // pte.u == 0: u bit is not set when the privilage is user
        else if(!permissions.u && lv_priv == 0)
          page_fault = True;
        // pte.u = 1 for supervisor: u bit is set and the privlage is supervisor 
        else if(permissions.u && lv_priv == 1)
          page_fault = True;
        // `logLevel( itlb, 0, $format("[%2d]ITLB: Sending PA:%h Trap:%b", hartid,physicaladdress, page_fault))

      return page_fault;
    endfunction 

    /*doc:rule: upon recieving any type of fence it will clear all the entries of the tlb
		*/
    rule rl_sfence(rg_sfence.sfence);
      for (Integer i = 0; i < `itlbsize; i = i + 1) begin
        v_vpn_tag[i] <= unpack(0);
      end
      rg_sfence.sfence <= False;
      rg_replace <= 0;
      `logLevel( itlb, 1, $format("ITLB[%2d]: SFencing Now simple sfence",hartid))      
    endrule:rl_sfence

    interface subifc_put_request_frm_core = interface Put
      method Action put (TLB_core_request#(vaddr, asidwidth) req) if(!rg_sfence.sfence && !rg_tlb_miss);

        `logLevel( tlb, 0, $format("[%2d]ITLB: received req: ",hartid,fshow(req)))

        
        Bit#(12) page_offset = req.address[11 : 0];
        Bit#(vpnsize) fullvpn = truncate(req.address >> 12);
        Bit#(satp_mode_size) satp_mode = truncateLSB(req.satp);
        Bit#(satp_mode_size) vssatp_mode = truncateLSB(req.vssatp); // will contain value from vs csr
        Bit#(satp_mode_size) hgatp_mode = truncateLSB(req.hgatp);
        //for V=0 its ssatp.asid and for V=1 its vssatp.asid
        Bit#(asidwidth) satp_asid = (req.v == 0)? truncate(req.satp >> v_ppnsize) : truncate(req.vssatp >> v_ppnsize);
        //for V=0 its ssatp.asid and for V=1 its hgatp.vmid
        Bit#(vmidwidth) hgatp_vmid = (req.v == 1)? truncate(req.hgatp >> v_ppnsize) : 0 ;

        /*doc:func: */
        function Bool fn_vtag_match (VPNTagH#(vpnsize, paddr, asidwidth, vmidwidth, ppnsize, max_varpages, subvpn) t);
          return t.gpa_permissions.v && t.hpa_permissions.v 
              && (({'1,t.pagemask} & fullvpn) == t.vpn)
              && (t.v == req.v)
              && ((t.v == 1 && t.vmid == hgatp_vmid) || (t.v==0 && t.vmid ==0))
              && ((t.v==1 && t.asid == satp_asid) || (t.v == 0 && (t.asid == satp_asid || t.hpa_permissions.g)) );
        endfunction

        Bit#(TLog#(`itlbsize)) tagmatch = 0;
        if(req.sfence_req.sfence)begin
          `logLevel( itlb, 0, $format("[%2d]ITLB: SFence received",hartid))
          rg_sfence <= req.sfence_req;
        end
        else begin
          let hit_entry = find(fn_vtag_match, readVReg(v_vpn_tag));
          Bool page_fault = False;
          Bool page_fault2 = False;
          Bit#(`causesize) cause = req.cause;
          Bool transparent_translation;
          if(req.v == 1)
            transparent_translation = (vssatp_mode == 0 && hgatp_mode == 0)? True: False;
          else 
            transparent_translation = (satp_mode == 0 || req.priv == 3)? True: False;
          // transparent translation
          if(transparent_translation)begin
            Bit#(paddr) coreresp = truncate(req.address);
            Bit#(TSub#(vaddr, paddr)) upper_bits = truncateLSB(req.address);
            Bool trap = |upper_bits == 1;
            ff_core_respone.enq(ITLB_core_response{address  : signExtend(coreresp),
                                                   trap     : trap,
                                                   cause    : `Inst_access_fault
                                                  `ifdef hypervisor   
                                                    ,gpa    : signExtend(coreresp)
                                                  `endif });
            `logLevel( itlb, 0, $format("[%2d]ITLB : Transparent Translation. PhyAddr: %h",hartid,coreresp))
          end
          else if (hit_entry matches tagged Valid .pte) begin//tlb hit
            `logLevel( itlb, 0, $format("[%2d]ITLB: Hit in TLB:",hartid,fshow(pte)))
            AccessTypes lv_access_types = unpack(req.access);
            let permissions = (req.v == 0)?pte.hpa_permissions:pte.gpa_permissions;
            Bit#(TMul#(TSub#(max_varpages,1),subvpn)) mask = truncate(pte.pagemask);
            Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_ppn = truncate(pte.ppn);
            Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_vpn = truncate(fullvpn);
            Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_pa =(mask&lower_ppn)|(~mask&lower_vpn);
            Bit#(lastppnsize) highest_ppn = truncateLSB(pte.ppn);
          `ifdef sv32
            Bit#(vaddr) physicaladdress = truncate({highest_ppn, lower_pa, page_offset});
          `else
            Bit#(vaddr) physicaladdress = zeroExtend({highest_ppn, lower_pa, page_offset});
          `endif

            `logLevel( itlb, 0, $format("[%2d]mask:%h",hartid,mask))
            `logLevel( itlb, 0, $format("[%2d]lower_ppn:%h",hartid,lower_ppn))
            `logLevel( itlb, 0, $format("[%2d]lower_vpn:%h",hartid,lower_vpn))
            `logLevel( itlb, 0, $format("[%2d]lower_pa:%h",hartid,lower_pa))
            `logLevel( itlb, 0, $format("[%2d]highest_ppn:%h",hartid,highest_ppn))

            // check for permission faults
          `ifndef sv32
            Bit#(TSub#(vaddr, maxvaddr)) unused_va = req.address[v_vaddr - 1 : v_maxvaddr];
            if(unused_va != signExtend(req.address[v_maxvaddr-1]))begin
              page_fault = True;
            end
          `endif
                        
            if (req.v == 1)begin 
              // check page fault           
              page_fault2 = fn_fault_check (pte.gpa_permissions, req.priv, req.v, True );
            end        
            page_fault = fn_fault_check (pte.hpa_permissions, req.priv, req.v, False );                                
            
            `logLevel( itlb, 0, $format("[%2d]ITLB: Sending PA:%h Trap:%b", hartid,physicaladdress, page_fault))
            if(page_fault2)
              cause = `Inst_guest_pagefault;
            else 
              cause = `Inst_pagefault;

            ff_core_respone.enq(ITLB_core_response{address  : truncate(physicaladdress),
                                                   trap     : page_fault || page_fault2,
                                                   cause    : cause 
                                                  `ifdef hypervisor   
                                                    ,gpa    : pte.gpa//but here the gpa inside the tlb will be used
                                                  `endif });
          end
          else begin
            // Send virtual - address and indicate it is an instruction access to the PTW
            `logLevel( itlb, 0, $format("[%2d]ITLB : TLBMiss. Sending Address to PTW:%h", hartid,req.address))
            rg_tlb_miss <= True;
          `ifdef perfmonitors
            wr_count_misses <= 1;
          `endif
            rg_miss_queue <= req.address;
            rg_miss_v <= req.v;
            ff_request_to_ptw.enq(PTWalk_tlb_request{address : req.address, access : 3,
                                                     priv: req.priv, mxr: req.mxr, sum: req.sum, satp: req.satp 
                                                  `ifdef hypervisor
                                                    ,v         : req.v 
                                                    ,hgatp     : req.hgatp
                                                    ,vssatp    : req.vssatp
                                                  `endif });
          end
        end
      endmethod
    endinterface;

    interface subifc_put_response_frm_ptw = interface Put
      method Action put(PTW_response_splitTLB#(vaddr, max_varpages, ppnsize, asidwidth, paddr) resp) if(rg_tlb_miss && !rg_sfence.sfence);
        let core_req = rg_miss_queue;
        let v = rg_miss_v;

        Bit#(asidwidth) satp_asid = (v == 0)? truncate(resp.asid) : truncate(resp.vssatp >> v_ppnsize);
        //for V=0 its ssatp.asid and for V=1 its hgatp.vmid
        Bit#(vmidwidth) hgatp_vmid = (v == 1)? truncate(resp.hgatp >> v_ppnsize) : 0 ;

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
        Bit#(TMul#(TSub#(max_varpages,1),subvpn)) lower_pa  =(mask&lower_ppn)|(~mask&lower_vpn);
        Bit#(lastppnsize) highest_ppn = truncateLSB(fullppn);
      `ifdef sv32
        Bit#(vaddr) physicaladdress = truncate({highest_ppn, lower_pa, page_offset});
      `else
        Bit#(vaddr) physicaladdress = zeroExtend({highest_ppn, lower_pa, page_offset});
      `endif

        ff_core_respone.enq(ITLB_core_response{ address : truncate(physicaladdress),
                                                trap    : resp.trap,
                                                cause   : resp.cause
                                              `ifdef hypervisor   
                                                ,gpa    : resp.gpa
                                              `endif });

        VPNTagH#(vpnsize, paddr, asidwidth, vmidwidth, ppnsize, max_varpages, subvpn) tag =VPNTagH{vpn              : {'1,mask} & fullvpn,
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
          `logLevel( itlb, 0, $format("[%2d]ITLB: Allocating index:%d for Tag:", hartid,rg_replace, fshow(tag)))
          v_vpn_tag[rg_replace] <= tag;
			    if ((valueOf(TExp#(TLog#(`itlbsize))) != valueOf(`itlbsize)) && (rg_replace == fromInteger(`itlbsize-1)))
			      rg_replace <= 0;
			    else
            rg_replace <= rg_replace + 1;
        end
        else begin
          `logLevel( itlb, 0, $format("[%2d]ITLB: Got an Error from PTW",hartid))
        end

        rg_tlb_miss <= False;
      endmethod
    endinterface;

    interface subifc_get_response_to_core = toGet(ff_core_respone);

    interface subifc_get_request_to_ptw = toGet(ff_request_to_ptw);

  `ifdef perfmonitors
    method mv_perf_counters = wr_count_misses;
  `endif
  endmodule

endpackage

