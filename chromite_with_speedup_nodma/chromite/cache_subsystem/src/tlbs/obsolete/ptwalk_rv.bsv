/* 
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy
Email id: shubham.roy@incoresemi.com
Details: pagetable walk 

--------------------------------------------------------------------------------------------------
*/
package ptwalk_rv;
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

  import dcache_types::*;
  import common_tlb_types :: * ;
  `include "mmu.defines"
  `include "Logger.bsv"
 
  /*doc:Ifc: interface to ptwalk module*/
  interface Ifc_ptwalk_rv;
    /* doc:subifc: to capture PTwalk request from tlb */
    interface Put#(PTWalk_tlb_request#(`xlen)) subifc_from_tlb;
    /* doc:subifc: to send response of PTwalk to tlb */
    interface Get#(PTWalk_tlb_response#(`xlen, `max_varpages )) subifc_to_tlb;
    /* doc:subifc: to send request to cache */ 
    interface Get#(DMem_request#(`vaddr, TMul#( `dwords, 8), `desize )) subifc_request_to_cache;// dword 4/8 for rv32/rv64
    /* doc:subifc: to capture response form cache */  
    interface Put#(DMem_core_response#(TMul#(`dwords, 8),`desize `ifdef hypervisor ,paddr `endif )) subifc_response_frm_cache;
    /* doc:subifc: to hold the pending cache to core request */
    interface Put#(DCache_core_request#(`vaddr, TMul#(`dwords, 8), `desize)) subifc_hold_req;
    (*always_enabled, always_ready*)
    /* doc:method: to sample in the data of satp csr */
    method Action ma_satp_from_csr (Bit#(`xlen) satp);
    (*always_enabled, always_ready*)
    /* doc:method: to sample in the data of mstatus csr */ 
    method Action ma_mstatus_from_csr (Bit#(`xlen) mstatus);
    (*always_enabled, always_ready*)
    /* doc:method: to sample in the current privilage */ 
    method Action ma_curr_priv (Bit#(2) curr_priv);
  endinterface

  typedef enum {ReSendReq, WaitForMemory, GeneratePTE} State deriving(Bits,Eq,FShow);

  /*doc:module: implements page table walk */
  module mkptwalk_rv(Ifc_ptwalk_rv);
    String ptwalk="";

    /*doc:fifo: holds request from tlb*/
    FIFOF#(PTWalk_tlb_request#(`xlen)) ff_req_queue <- mkLFIFOF();  //from tlb
    /*doc:fifo: holds the response to tlb */ 
    FIFOF#(PTWalk_tlb_response#(`xlen, `max_varpages)) ff_response <- mkLFIFOF();   // to tlb
    /*doc:fifo: hold the request to cache */
    FIFOF#(DMem_request#(`vaddr, TMul#( `dwords, 8), `desize )) ff_memory_req <- mkLFIFOF();   //request to cache
    /*doc:fifo: hold the response from cache */
    FIFOF#(DMem_core_response#(TMul#(`dwords, 8),`desize `ifdef hypervisor ,paddr `endif )) ff_memory_response <- mkLFIFOF();   // response from cache
    /*doc:fifo: hold the request of DCahce_core_request type */
    FIFOF#(DCache_core_request#(`vaddr, TMul#(`dwords, 8), `desize)) ff_hold_req <- mkLFIFOF();    // hold rewuest

    /*doc:wire: this wire holds input from satp csr */
    Wire#(Bit#(`xlen)) wr_satp <- mkWire();
    /*doc:wire: this wire holds input from mstatus csr */
    Wire#(Bit#(`xlen)) wr_mstatus <- mkWire();
    /*doc:wire: this wire holds privilage mode  */
    Wire#(Bit#(2)) wr_priv <- mkWire();
   
    Bit#(`ppnsize) satp_ppn = truncate(wr_satp);
    Bit#(`asidwidth) satp_asid = wr_satp[`asidwidth - 1+`ppnsize : `ppnsize];
    Bit#(`satp_mode_size) satp_mode = truncateLSB(wr_satp);

    // sampling the important data from the csr 
    // the bit position are same for rv32 and rv64
    Bit#(1) mxr = wr_mstatus[19];
    Bit#(1) sum = wr_mstatus[18];
    Bit#(2) mpp = wr_mstatus[12:11];
    Bit#(1) mprv = wr_mstatus[17];

    /*doc:reg: this register holds the epoch value */      
    Reg#(Bit#(`desize)) rg_hold_epoch <- mkRegA(0);
    /*doc:reg: use to tell which page table level you are in similar to i in algo */
    Reg#(Bit#(TLog#(`max_varpages))) rg_levels <- mkRegA(0); 
    /*doc:reg: this register is named "a" to keep coherence with the algorithem provided in the spec */
    Reg#(Bit#(TAdd#(`ppnsize, `page_offset))) rg_a <- mkRegA(0);  
    /*doc:reg: to hold the current state of FSM */
    Reg#(State) rg_state<- mkRegA(GeneratePTE);

    /*doc:wire: used to fire deq_holding_fifo rule */
    Wire#(Bool) wr_deq_holding_ff <- mkWire();

    /*doc:func: function to generate memory request packets */
    function DMem_request#(`vaddr, TMul#( `dwords, 8), `desize ) fn_gen_dcache_packet (PTWalk_tlb_request#(`xlen) lv_req, 
                                                   Bool lv_reqtype, Bool lv_trap, Bit#(`causesize) lv_cause);
      return DMem_request{address     : lv_req.address,
                          epochs      : rg_hold_epoch,
                          size        : 3,
                          access      : 0,
                          fence       : False,
                          writedata   : zeroExtend(lv_cause),
                        `ifdef atomic
                          atomic_op   : ?,
                        `endif
                          sfence      : False,
                          ptwalk_req  : lv_reqtype,
                          ptwalk_trap : lv_trap};
    endfunction

    /*doc:func: function to check for mis-alignment given a page level and pte by checking the ppn */
    function Bool fn_ppn_comparision (Bit#(TSub#(`xlen, 10)) lv_pte_without_perm, Bit#(TLog#(`max_varpages)) lv_rg_level );
      Bit#(TSub#(`xlen, 10)) lv_ppn_mask [`max_varpages] ;
      for(Integer i = 0; i<`max_varpages -1 ; i= i+1)
        lv_ppn_mask[i] = (1 << `subvpn*(i+1)) - 1;
      
      return((lv_pte_without_perm & lv_ppn_mask[lv_rg_level-1]) != 0);

    endfunction
    /*doc:func: function to check if the pte has the napot bits set according to the spec */
    function Bool fn_napot_bits_check(Bit#(TSub#(`xlen, 10)) lv_ppn);
      Bit#(`subvpn) lv_ppn0 = lv_ppn[`subvpn - 1: 0];
      
      Bit#(4) lv_napot = 4'b1000;
      return (lv_ppn0[3:0] == lv_napot);
                
    endfunction 

    /*doc:rule: rule to resent core request to cache */  
    rule rl_resend_core_req_to_cache(rg_state==ReSendReq);
      `logLevel( ptwalk, 2, $format("PTWALK: Resending Core request back to DCache: ", 
                                    fshow(ff_hold_req.first)))
      let lv_request = ff_req_queue.first;
      let lv_hold_req = ff_hold_req.first;
      ff_memory_req.enq(DMem_request{address    : lv_hold_req.address,
                                     epochs     : lv_hold_req.epochs,
                                     size       : lv_hold_req.size,
                                     fence      : False,
                                     access     : lv_hold_req.access,
                                     writedata  : lv_hold_req.data,
      `ifdef atomic
                                     atomic_op  : lv_hold_req.atomic_op,
      `endif
                                     sfence     : False,
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
      `logLevel( ptwalk, 2, $format("PTWALK: Recieved Request: ",fshow(ff_req_queue.first)))

      // vpn segregation 
      Bit#(`subvpn) lv_vpn[`max_varpages];
      for(Integer i = 0;i < `max_varpages; i= i+1) begin  
        lv_vpn[i] = lv_request.address[(i+1)* `subvpn + `page_offset -1 : i*`subvpn + `page_offset];
      end
      
      Bit#(TLog#(`max_varpages)) lv_max_levels = case (satp_mode) matches
        `ifdef sv32 1: 1; `endif    //sv32
        `ifdef sv39 8: 2; `endif    //sv39
        `ifdef sv48 8: 2; 9: 3; `endif    //sv48
        `ifdef sv57 8: 2; 9: 3; 10: 4; `endif   //sv57
        default: fromInteger(`max_varpages - 1);
      endcase;
      
      Bit#(TAdd#(`ppnsize, `page_offset)) lv_a = rg_levels==(lv_max_levels)?{satp_ppn,12'b0}:rg_a;// 34/56 
      //sign extended or zero extended
      Bit#(`paddr) _a = truncate(lv_a); // -0-.-22/44-.-12(0)-
      Bit#(TSub#(`page_offset, `subvpn)) _app_zero = 0;
      Bit#(`paddr) lv_pte_address = _a + zeroExtend({lv_vpn[rg_levels], _app_zero}); 
      lv_request.address = zeroExtend(lv_pte_address);    

      `logLevel( ptwalk, 2, $format("PTWALK: Sending PTE - Address to DMEM:%h",lv_pte_address))
      ff_memory_req.enq(fn_gen_dcache_packet(lv_request, True, False,?));
      rg_state<=WaitForMemory;
    endrule

    /*doc:rule: rule to perform differnt check on page table entry */
    rule rl_check_pte(rg_state==WaitForMemory);
      let lv_request = ff_req_queue.first;
      
      // vpn segregation 
      Bit#(`subvpn) lv_vpn[`max_varpages];
      for(Integer i = 0;i < `max_varpages; i= i+1) begin  
        lv_vpn[i] = lv_request.address[(i+1)* `subvpn + `page_offset -1 : i*`subvpn + `page_offset];
      end
      
      `logLevel( ptwalk, 2, $format("PTWALK: For Request: ",fshow(ff_req_queue.first)))
      `logLevel( ptwalk, 2, $format("PTWALK: Memory Response: ",fshow(ff_memory_response.first)))

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
      Bit#(2) lv_priv = mprv==0?wr_priv:mpp;
      AccessTypes lv_access_types = unpack(lv_request.access);
      
      `logLevel( ptwalk, 2, $format("PTWALK: Permissions", fshow(lv_permissions)))
      
      `ifdef sv32 
        Bool lv_pte_pbmt = False;
        Bool lv_pte_n = False;
        Bool lv_reserve_bit_set = False;
      `else
        Bit#(7) _reserve_bits = lv_response.word[60:54];
        Bool lv_reserve_bit_set = _reserve_bits != 0;

        Bit#(2) _pbmt = lv_response.word[62:61];
        Bit#(1) _n = lv_response.word[63];
        Bool lv_pte_pbmt = _pbmt!= 0;
        Bool lv_pte_n = _n!= 0;
      `endif

      Bit#(TSub#(`xlen, 10)) _pte = truncateLSB(lv_response.word);
      // from spec: if the requested memory access is allowed by the pte.r, pte.w, pte.x, and 
      // pte.u bits, given the current privilege mode and the value of the SUM and MXR fields of 
      // the mstatus register. If not, stop and raise a page-fault exception
      Bool _c = (lv_permissions.u) ? ((lv_priv == 'b01) && (lv_access_types == Fetch|| !unpack(sum))) : (lv_priv != 'b01);
      Bool _d = lv_access_types == Fetch ? !(lv_permissions.x) :
                lv_access_types == Load  ? !(lv_permissions.r) && !(unpack(mxr) && (lv_permissions.x)) :
                                        !((lv_permissions.r) && (lv_permissions.w));

      // from spec: if any bits or encodings that are reserved for future standard use are set 
      // within pte, stop and raise a page-fault exception
      if (lv_reserve_bit_set) begin
        lv_fault=True;
        `logLevel( ptwalk, 0, $format("PTWALK: Fault Reason - Reserved Bits Set"))
      end

    `ifdef svnapot
      else if(lv_pte_n) begin
        if(!fn_napot_bits_check(_pte)) begin
          lv_fault = True;
          `logLevel( ptwalk, 0, $format("PTWALK: Fault Reason - NAPOT Bits Check Failed"))
        end
      end
    `endif
  
      // from spec: For non-leaf PTEs, the D, A, and U bits are reserved for future standard use. Until their 
      // use is defined by a standard extension, they must be cleared by software for forward 
      // compatibility.
      else if(!lv_permissions.x && !lv_permissions.w && !lv_permissions.r && lv_permissions.v ) begin //next level page 
        if(lv_permissions.d || lv_permissions.a || lv_permissions.u || lv_pte_n || lv_pte_pbmt) begin
          lv_fault=True;
          `logLevel( ptwalk, 0, $format("PTWALK: Fault Reason - Next Level PTW has D|A|U|N|PBMT set"))
        end
      end
      else if ( _c ) begin
        lv_fault=True;
        `logLevel( ptwalk, 0, $format("PTWALK: Fault Reason - User permissions Failed"))
      end
      // from spec: If pte.v = 0, or if pte.r = 0 and pte.w = 1 stop and raise a page-fault exception
      else if (!lv_permissions.v || (!lv_permissions.r && lv_permissions.w)) begin
        lv_fault=True;
        `logLevel( ptwalk, 0, $format("PTWALK: Fault Reason - Valid not Set or Reserved RW settings"))
      end
      else if (_d) begin
        lv_fault=True;
        `logLevel( ptwalk, 0, $format("PTWALK: Fault Reason - Access permissions failed"))
      end
      // from spec: A superpage must be virtually and physically aligned a page-fault exception is 
      // raised if the physical address is insufficiently aligned.
      else if(fn_ppn_comparision(_pte, rg_levels)) begin // mis-allign check
        lv_fault=True;
        `logLevel( ptwalk, 0, $format("PTWALK: Fault Reason - Mis Aligned Page"))
      end
      // form spec: When a virtual page is accessed and the A bit is clear, or is written and 
      // the D bit is clear, a page-fault exception is raised.
      else if (!lv_permissions.a || 
              ((lv_access_types == Store || lv_access_types == Atomic) && !lv_permissions.d)) begin
        lv_fault = True;
        `logLevel( ptwalk, 0, $format("PTWALK: Fault Reason - A|D bits not set"))
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
         
        `logLevel( ptwalk, 2, $format("PTWALK: Generated Error. Cause:%d",lv_cause))
        
        if(lv_access_types != Fetch)
          ff_memory_req.enq(fn_gen_dcache_packet(lv_request, False, True, lv_cause));
        ff_response.enq(PTWalk_tlb_response{pte : truncate(lv_response.word),
                                        levels  : rg_levels,
                                        trap    : lv_trap,
                                        cause   : lv_cause});
        if(lv_access_types != Fetch)
           wr_deq_holding_ff <= True;
        ff_req_queue.deq();
        rg_state<=GeneratePTE;
      end
      else if (!lv_permissions.r && !lv_permissions.x)begin // this pointer to next level
        rg_levels<=rg_levels-1;

        // 10 bits from the LSB are used for permission
        // 10 bits from MSB are for SVNAOP and some are reserved
        // rg_a<={response.word[`ppnsize + 10 -1:10],12'b0};
        // rg_a<={(truncate(truncateLSB(response.word,10)),12'b0};
        Bit#(TSub#(`xlen, 10)) _response = truncateLSB(lv_response.word);
        // rg_a<=truncate({_response,12'b0});// will truncate to fit the ppn size
      `ifdef svnapot
        if(rg_levels == 0)
          rg_a <= {rg_a[55:4], lv_vpn[0][3:0]};
        else
      `endif
          rg_a<=truncate({_response,12'b0});// will truncate to fit the ppn size

        rg_state<=GeneratePTE;
        `logLevel( ptwalk, 2, $format("PTWALK: Pointer to NextLevel:%h Levels:%d", {lv_response.word[31 : 10], 12'b0}, 
                                      rg_levels))
      end
      else begin // Leaf PTE found
        ff_response.enq(PTWalk_tlb_response{pte     : truncate(lv_response.word),
                                        levels  : rg_levels,
                                        trap    : lv_trap,
                                        cause   : lv_cause});
        `logLevel( ptwalk, 2, $format("PTWALK: Found Leaf PTE:%h levels: %d", lv_response.word,
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
      method Action put(PTWalk_tlb_request#(`xlen) a);
        ff_req_queue.enq(a);
        rg_levels <= case (satp_mode) matches
          `ifdef sv32 1: 1; `endif //sv32
          `ifdef sv39 8: 2; `endif //sv39
          `ifdef sv48 8: 2; 9: 3;  `endif //sv48
          `ifdef sv57 8: 2; 9: 3; 10: 4; `endif //sv57
          default: rg_levels;
        endcase;
      endmethod
    endinterface;

    interface subifc_to_tlb              = toGet(ff_response);
    
    interface subifc_hold_req            = interface Put
      /* doc:method: to set hold epoch register and enq the request */
      method Action put(DCache_core_request#(`vaddr, TMul#(`dwords, 8), `desize) req);
        rg_hold_epoch<=req.epochs;
        ff_hold_req.enq(req);
      endmethod
    endinterface;

    interface subifc_request_to_cache    = toGet(ff_memory_req);

    interface subifc_response_frm_cache  = toPut(ff_memory_response);

    method Action ma_satp_from_csr (Bit#(`xlen) satp);
      wr_satp <= satp;
    endmethod

    method Action ma_curr_priv (Bit#(2) priv);
      wr_priv <= priv;
    endmethod

    method Action ma_mstatus_from_csr (Bit#(`xlen) mstatus);
      wr_mstatus <= mstatus;
    endmethod
  endmodule
endpackage
