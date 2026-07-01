/* 
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: pagetable walk 

--------------------------------------------------------------------------------------------------
*/
package ptwalk_rv_supervisor;
  import Vector::*;
  import FIFOF::*;
  import DReg::*;
  import SpecialFIFOs::*;
  import BRAMCore::*;
  import FIFO::*;
  import GetPut::*;

  import dcache_types::*;
  import mmu_types :: * ;
  `include "mmu.defines"
  `include "Logger.bsv"
 
  /*doc:Ifc: interface to ptwalk module*/
  interface Ifc_ptwalk_rv# (
                            numeric type xlen,
                            numeric type paddr,
                            numeric type max_varpages,
                            numeric type ppnsize,
                            numeric type lastppnsize,
                            numeric type subvpn,
                            numeric type page_offset,
                            numeric type asidwidth,
                            numeric type satp_mode_size,
                            numeric type svnapot
                          );
    /* doc:subifc: to capture PTwalk request from tlb */
    interface Put#(PTWalk_tlb_request#(xlen)) subifc_from_tlb;
    /* doc:subifc: to send response of PTwalk to tlb */
    interface Get#(PTW_response_splitTLB#(xlen, max_varpages, ppnsize, asidwidth, paddr )) subifc_to_tlb;
    /* doc:subifc: to send request to cache */ 
    interface Get#(DMem_request#(xlen, TMul#( `dwords, 8), `desize )) subifc_request_to_cache;// dword 4/8 for rv32/rv64
    /* doc:subifc: to capture response form cache */  
    interface Put#(DMem_core_response#(TMul#(`dwords, 8),`desize `ifdef hypervisor ,paddr `endif )) subifc_response_frm_cache;
    /* doc:subifc: to hold the pending cache to core request */
    interface Put#(DCache_core_request#(xlen, TMul#(`dwords, 8), `desize)) subifc_hold_req;
  endinterface

  typedef enum {ReSendReq, WaitForMemory, GeneratePTE} State deriving(Bits,Eq,FShow);

  /*doc:module: implements page table walk */
  module mkptwalk_rv#(parameter Bit#(32) hartid)(Ifc_ptwalk_rv#(xlen, paddr, max_varpages, ppnsize, 
                      lastppnsize, subvpn, page_offset, asidwidth, satp_mode_size, svnapot))
      provisos(
        // Add#(1,TMul#(TLog#(TDiv#(xlen,32)),3),satp_mode_size),
      `ifdef RV64
        Add#(a__, xlen, 64), // xlen should be <= 64
        Add#(xlen, f__, 74),
      `else
        Add#(a__, xlen, 32), // xlen should be <= 32
        Add#(xlen, f__, 42),
      `endif
        Add#(b__, ppnsize, xlen), // ppnsize <= xlen
        Add#(c__, paddr, TAdd#(ppnsize, page_offset)), // paddr <= ppnsize+pageoffset
        Add#(d__, TAdd#(subvpn, TSub#(page_offset, subvpn)), paddr), // subvpn+[3/2] <= paddr
        Add#(e__, TAdd#(ppnsize, page_offset), TAdd#(TSub#(xlen, 10), 12)),
        Add#(g__, paddr, xlen),
        Add#(satp_mode_size, h__, xlen),
        Add#(i__, 4, TAdd#(ppnsize, page_offset)),
        Add#(j__, asidwidth, xlen),
        Add#(k__, 4, ppnsize)
      );

    let v_xlen          = valueOf(xlen);
    let v_paddr         = valueOf(paddr);
    let v_max_varpages  = valueOf(max_varpages);
    let v_ppnsize       = valueOf(ppnsize);
    let v_lastppnsize   = valueOf(lastppnsize);
    let v_subvpn        = valueOf(subvpn);
    let v_page_offset   = valueOf(page_offset);
    let v_asidwidth     = valueOf(asidwidth);
    let v_satp_mode_size = valueOf(satp_mode_size);
    let v_svnapot       = valueOf(svnapot);

    String ptwalk="";

    /*doc:fifo: holds request from tlb*/
    FIFOF#(PTWalk_tlb_request#(xlen)) ff_req_queue <- mkBypassFIFOF();  //from tlb
    /*doc:fifo: holds the response to tlb */ 
    FIFOF#(PTW_response_splitTLB#(xlen, max_varpages, ppnsize, asidwidth, paddr)) ff_response <- mkSizedFIFOF(2);   // to tlb
    /*doc:fifo: hold the request to cache */
    FIFOF#(DMem_request#(xlen, TMul#( `dwords, 8), `desize )) ff_memory_req <- mkSizedFIFOF(2);   //request to cache
    /*doc:fifo: hold the response from cache */
    FIFOF#(DMem_core_response#(TMul#(`dwords, 8),`desize `ifdef hypervisor ,paddr `endif )) ff_memory_response <- mkBypassFIFOF();   // response from cache
    /*doc:fifo: hold the request of DCahce_core_request type */
    FIFOF#(DCache_core_request#(xlen, TMul#(`dwords, 8), `desize)) ff_hold_req <- mkSizedFIFOF(2);    // hold rewuest

    /*doc:reg: this register holds the epoch value */      
    Reg#(Bit#(`desize)) rg_hold_epoch <- mkRegA(0);
    /*doc:reg: use to tell which page table level you are in similar to i in algo */
    Reg#(Bit#(TLog#(max_varpages))) rg_levels <- mkRegA(0); 
    /*doc:reg: this register is named "a" to keep coherence with the algorithem provided in the spec */
    Reg#(Bit#(TAdd#(ppnsize, page_offset))) rg_a <- mkRegA(0);  
    /*doc:reg: to hold the current state of FSM */
    Reg#(State) rg_state<- mkRegA(GeneratePTE);

    /*doc:wire: used to fire deq_holding_fifo rule */
    Wire#(Bool) wr_deq_holding_ff <- mkWire();

    /*doc:func: function to generate memory request packets */
    function DMem_request#(xlen, TMul#( `dwords, 8), `desize ) fn_gen_dcache_packet (PTWalk_tlb_request#(xlen) lv_req, 
                                                   Bool lv_reqtype, Bool lv_trap, Bit#(`causesize) lv_cause, Bit#(2) priv,
                                                   Bit#(1) mxr, Bit#(1) sum, Bit#(xlen) satp);
      return DMem_request{address     : lv_req.address,
                          epochs      : rg_hold_epoch,
                          size        : 3,
                          access      : 0,
                          fence       : False,
                          writedata   : zeroExtend(lv_cause),
                          priv        : priv
                          ,mxr        : mxr 
                          ,sum        : sum 
                          ,satp       : satp,

                        `ifdef atomic
                          atomic_op   : ?,
                        `endif
                          sfence_req  : SfenceReq{sfence: False},
                          ptwalk_req  : lv_reqtype,
                          ptwalk_trap : lv_trap};
    endfunction

    /*doc:func: function to check for mis-alignment given a page level and pte by checking the ppn */
    function Bool fn_ppn_comparision (Bit#(TSub#(xlen, 10)) lv_pte_without_perm, Bit#(TLog#(max_varpages)) lv_rg_level );
      Bit#(TSub#(xlen, 10)) lv_ppn_mask [v_max_varpages] ;
      for( Integer i = 0; i<v_max_varpages ; i= i+1)
        lv_ppn_mask[i] = (1 << v_subvpn*(i+1)) - 1;
      
      return((lv_pte_without_perm & lv_ppn_mask[lv_rg_level-1]) != 0);

    endfunction
    /*doc:func: function to check if the pte has the napot bits set according to the spec */
    function Bool fn_napot_bits_check(Bit#(TSub#(xlen, 10)) lv_ppn);
      Bit#(subvpn) lv_ppn0 = lv_ppn[v_subvpn - 1: 0];
      
      Bit#(4) lv_napot = 4'b1000;
      return (lv_ppn0[3:0] == lv_napot);
                
    endfunction 

    /*doc:rule: rule to resent core request to cache */  
    rule rl_resend_core_req_to_cache(rg_state==ReSendReq);
      `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Resending Core request back to DCache: ",hartid, 
                                    fshow(ff_hold_req.first)))
      let lv_request = ff_req_queue.first;
      let lv_hold_req = ff_hold_req.first;
      ff_memory_req.enq(DMem_request{address    : lv_hold_req.address,
                                     epochs     : lv_hold_req.epochs,
                                     size       : lv_hold_req.size,
                                     fence      : False,
                                     access     : lv_hold_req.access,
                                     writedata  : lv_hold_req.data,
                                     priv       : lv_request.priv,
                                     mxr        : lv_request.mxr ,
                                     sum        : lv_request.sum ,
                                     satp       : lv_request.satp,

      `ifdef atomic
                                     atomic_op  : lv_hold_req.atomic_op,
      `endif
                                     sfence_req : SfenceReq{sfence: False},
                                     ptwalk_req : False,
                                     ptwalk_trap : False});
        ff_req_queue.deq();
        rg_state<=GeneratePTE;
      wr_deq_holding_ff <= True;
    endrule

    /*doc:rule: rule to dequeue from ff_hold_req */
    rule rl_deq_holding_fifo(wr_deq_holding_ff);
      ff_hold_req.deq;
    endrule

    /*doc:rule: rule to generate page table entry */
    rule rl_generate_pte(rg_state==GeneratePTE);
      let lv_request = ff_req_queue.first;
      `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Recieved Request: ",hartid,fshow(ff_req_queue.first)))

      // vpn segregation 
      Bit#(subvpn) lv_vpn[v_max_varpages];
      for(Integer i = 0;i < v_max_varpages; i= i+1) begin  
        lv_vpn[i] = lv_request.address[(i+1)* v_subvpn + v_page_offset -1 : i*v_subvpn + v_page_offset];
      end
      Bit#(satp_mode_size) curr_satp_mode = truncateLSB(lv_request.satp);
      Bit#(ppnsize) satp_ppn = truncate(lv_request.satp);      
      Bit#(TLog#(max_varpages)) lv_max_levels = (v_max_varpages==2 && curr_satp_mode==1)? 1: 
                                                (v_max_varpages >=3 && curr_satp_mode==8)?2:
                                                (v_max_varpages >=4 && curr_satp_mode==9)?3:
                                                (v_max_varpages ==5 && curr_satp_mode==10)?4:
                                                0;
      
      Bit#(TAdd#(ppnsize, page_offset)) lv_a = rg_levels==(lv_max_levels)?{satp_ppn,'d0}:rg_a;//  
      //sign extended or zero extended
      Bit#(paddr) _a = truncate(lv_a); // -0-.-22/44-.-12(0)-
      Bit#(TSub#(page_offset, subvpn)) _app_zero = 0;
      Bit#(paddr) lv_pte_address = _a + zeroExtend({lv_vpn[rg_levels], _app_zero}); 
      lv_request.address = zeroExtend(lv_pte_address);    

      `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Sending PTE - Address to DMEM:%h",hartid,lv_pte_address))
      ff_memory_req.enq(fn_gen_dcache_packet(lv_request, True, False,?, lv_request.priv,lv_request.mxr,lv_request.sum, lv_request.satp));
      rg_state<=WaitForMemory;
    endrule

    /*doc:rule: rule to perform differnt check on page table entry */
    rule rl_check_pte(rg_state==WaitForMemory);
      let lv_request = ff_req_queue.first;
      
      // vpn segregation 
      Bit#(subvpn) lv_vpn[v_max_varpages];
      for(Integer i = 0;i < v_max_varpages; i= i+1) begin  
        lv_vpn[i] = lv_request.address[(i+1)* v_subvpn + v_page_offset -1 : i*v_subvpn + v_page_offset];
      end
      
      `logLevel( ptwalk, 2, $format("[%2d]PTWALK: For Request: ",hartid,fshow(ff_req_queue.first)))
      `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Memory Response: ",hartid,fshow(ff_memory_response.first)))

      let lv_response = ff_memory_response.first();
      ff_memory_response.deq;

      // Fault or trap cheking logic Start
      Bool lv_fault=False;
      Bit#(`causesize) lv_cause=0;
      Bool lv_trap=False;
      // 10 bit are reserved for permission for all the virtulization scheme
      // capture the permissions of the hit entry from the TLBs
      // 7 6 5 4 3 2 1 0
      // D A G U X W R V
      TLB_permissions lv_permissions=bits_to_permission(truncate(lv_response.word));
      AccessTypes lv_access_types = unpack(lv_request.access);
      
      `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Permissions",hartid, fshow(lv_permissions)))
      
      Bool lv_pte_pbmt = False;
      Bool lv_pte_n = False;
      Bool lv_reserve_bit_set = False;

      if (v_max_varpages > 2) begin
        Bit#(7) _reserve_bits = lv_response.word[60:54];
        lv_reserve_bit_set = _reserve_bits != 0;

        Bit#(2) _pbmt = lv_response.word[62:61];
        Bit#(1) _n = lv_response.word[63];
         lv_pte_pbmt = _pbmt!= 0;
         lv_pte_n = _n!= 0;
      end

      Bit#(TSub#(xlen, 10)) _pte = truncateLSB(lv_response.word);
      // from spec: if the requested memory access is allowed by the pte.r, pte.w, pte.x, and 
      // pte.u bits, given the current privilege mode and the value of the SUM and MXR fields of 
      // the mstatus register. If not, stop and raise a page-fault exception
      Bool _c = (lv_permissions.u) ? ((lv_request.priv == 'b01) && (lv_access_types == Fetch|| !unpack(lv_request.sum))) : (lv_request.priv != 'b01);
      Bool _d = lv_access_types == Fetch ? !(lv_permissions.x) :
                lv_access_types == Load  ? !(lv_permissions.r) && !(unpack(lv_request.mxr) && (lv_permissions.x)) :
                                        !((lv_permissions.r) && (lv_permissions.w));

      // from spec: if any bits or encodings that are reserved for future standard use are set 
      // within pte, stop and raise a page-fault exception
      if (lv_reserve_bit_set) begin // check is any of the reserved bits are set
        lv_fault=True;
        `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - Reserved Bits Set",hartid))
      end
      else if(lv_pte_n && valueOf(svnapot)==1) begin
        if(!fn_napot_bits_check(_pte)) begin
          lv_fault = True;
          `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - NAPOT Bits Check Failed",hartid))
        end
      end
      // from spec: For non-leaf PTEs, the D, A, and U bits are reserved for future standard use. Until their 
      // use is defined by a standard extension, they must be cleared by software for forward 
      // compatibility.
      else if(!lv_permissions.x && !lv_permissions.w && !lv_permissions.r && lv_permissions.v ) begin//next level page 
        if(lv_permissions.d || lv_permissions.a || lv_permissions.u || lv_pte_n || lv_pte_pbmt) begin
          lv_fault=True;
          `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - Next Level PTW has D|A|U|N|PBMT set",hartid))
        end
      end
      else if ( _c ) begin
        lv_fault=True;
        `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - User permissions Failed",hartid))
      end
      // from spec: If pte.v = 0, or if pte.r = 0 and pte.w = 1 stop and raise a page-fault exception
      else if (!lv_permissions.v || (!lv_permissions.r && lv_permissions.w)) begin
        lv_fault=True;
        `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - Valid not Set or Reserved RW settings",hartid))
      end
      else if (_d) begin
        lv_fault=True;
        `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - Access permissions failed",hartid))
      end
      // from spec: A superpage must be virtually and physically aligned a page-fault exception is 
      // raised if the physical address is insufficiently aligned.
      else if(fn_ppn_comparision(_pte, rg_levels) && rg_levels !=0 ) begin // mis-allign check
        lv_fault=True;
        `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - Mis Aligned Page",hartid))
      end
      // form spec: When a virtual page is accessed and the A bit is clear, or is written and 
      // the D bit is clear, a page-fault exception is raised.
      else if (!lv_permissions.a || 
              ((lv_access_types == Store || lv_access_types == Atomic) && !lv_permissions.d)) begin
        lv_fault = True;
        `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - A|D bits not set",hartid))
      end
 
      // Fault or trap cheking logic End  
      
      if(lv_fault || lv_response.trap) begin  
        lv_trap=True;
        if(lv_response.trap)begin
          case(lv_access_types) matches
            Fetch:  lv_cause = `Inst_access_fault;  // Fetch
            Load:   lv_cause = `Load_access_fault;  // Load
            default:lv_cause = `Store_access_fault; // Atomic
          endcase
        end
          
        else if(lv_fault)begin
          case(lv_access_types) matches
            Fetch:  lv_cause = `Inst_pagefault;  // Fetch
            Load:   lv_cause = `Load_pagefault;  // Load
            default:lv_cause = `Store_pagefault; // Atomic
          endcase
        end
         
        `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Generated Error. Cause:%d",hartid,lv_cause))
        
        if(lv_access_types != Fetch)
          ff_memory_req.enq(fn_gen_dcache_packet(lv_request, False, True, lv_cause, lv_request.priv,
                                                  lv_request.mxr, lv_request.sum, lv_request.satp));
        Bit#(asidwidth) satp_asid = truncate(lv_request.satp >> v_ppnsize);
        Bit#(4) napot_repl = lv_vpn[0][3:0];//replace napot_bits from ppn0 with the napot_bits of VPN
        Bit#(ppnsize) ppn = (rg_levels == 0 && lv_pte_n && valueOf(svnapot)==1 && fn_napot_bits_check(_pte) && lv_pte_n)? {lv_response.word[v_ppnsize +9:14], napot_repl} : lv_response.word[v_ppnsize +9:10]; 
        ff_response.enq(PTW_response_splitTLB{va          : lv_request.address, 
                                              asid        : satp_asid,
                                              ppn         : ppn, 
                                              permissions : lv_permissions,
                                              trap        : lv_trap,
                                              cause       : lv_cause,
                                              levels      : rg_levels,
                                              n           : (fromInteger(v_svnapot) & pack(lv_pte_n) & pack(fn_napot_bits_check(_pte)))
                                              });
        if(lv_access_types != Fetch)
           wr_deq_holding_ff <= True;
        ff_req_queue.deq();
        rg_state<=GeneratePTE;
      end
      else if (!lv_permissions.r && !lv_permissions.x)begin // this pointer to next level
        rg_levels<=rg_levels-1;

        // 10 bits from the LSB are used for permission
        // 10 bits from MSB are for SVNAOPT and some are reserved
        Bit#(TSub#(xlen, 10)) _response = truncateLSB(lv_response.word);
        // if(rg_levels == 0 && valueOf(svnapot)==1) begin
        //   Bit#(4) _l = lv_vpn[0][3:0];
        //   rg_a <= {truncateLSB(rg_a), _l};
        // end
        // else
        rg_a<=truncate({_response,12'b0});// will truncate to fit the ppn size

        rg_state<=GeneratePTE;
        `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Pointer to NextLevel:%h Levels:%d",hartid, {lv_response.word[31 : 10], 12'b0}, 
                                      rg_levels))
      end
      else begin // Leaf PTE found
        Bit#(asidwidth) satp_asid = truncate(lv_request.satp >> v_ppnsize);
        Bit#(4) napot_repl = lv_vpn[0][3:0];//replace napot_bits from ppn0 with the napot_bits of VPN
        Bit#(ppnsize) ppn = (rg_levels == 0 && lv_pte_n && valueOf(svnapot)==1 && fn_napot_bits_check(_pte) && lv_pte_n)? {lv_response.word[v_ppnsize +9:14], napot_repl} : lv_response.word[v_ppnsize +9:10]; 
        ff_response.enq(PTW_response_splitTLB{va          : lv_request.address, 
                                              asid        : satp_asid,
                                              ppn         : ppn, 
                                              permissions : lv_permissions,
                                              trap        : lv_trap,
                                              cause       : lv_cause,
                                              levels      : rg_levels,
                                              n           : (fromInteger(v_svnapot) & pack(lv_pte_n) & pack(fn_napot_bits_check(_pte)))
                                              });
        `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Found Leaf PTE:%h levels: %d",hartid, lv_response.word,
                                      rg_levels))
        if(lv_access_types != Fetch)
          rg_state<=ReSendReq;
        else begin
          rg_state<=GeneratePTE;
          ff_req_queue.deq;
        end
        
      end
    endrule

    interface subifc_from_tlb            = interface Put
      /* doc:method: to set level register according to satp mode */
      method Action put(PTWalk_tlb_request#(xlen) a);
        `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Got new request:",hartid, fshow(a)))
        ff_req_queue.enq(a);
        Bit#(satp_mode_size) curr_satp_mode = truncateLSB(a.satp);
        let lv_levels = (v_max_varpages==2 && curr_satp_mode == 1)? 1: 
                    (v_max_varpages >=3 && curr_satp_mode==8)?2:
                    (v_max_varpages >=4 && curr_satp_mode==9)?3:
                    (v_max_varpages ==5 && curr_satp_mode==10)?4:
                    rg_levels;
        `logLevel( ptwalk, 0, $format("[%2d]PTWALK: rg_levels:%d",hartid, lv_levels))
        rg_levels <= lv_levels;
      endmethod
    endinterface;

    interface subifc_to_tlb              = toGet(ff_response);
    
    interface subifc_hold_req            = interface Put
      /* doc:method: to set hold epoch register and enq the request */
      method Action put(DCache_core_request#(xlen, TMul#(`dwords, 8), `desize) req);
        rg_hold_epoch<=req.epochs;
        ff_hold_req.enq(req);
      endmethod
    endinterface;

    interface subifc_request_to_cache    = toGet(ff_memory_req);

    interface subifc_response_frm_cache  = toPut(ff_memory_response);

  endmodule
endpackage
