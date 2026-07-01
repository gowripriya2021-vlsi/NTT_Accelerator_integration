/* 
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy, Neel Gala
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: pagetable walk presently it assumes both hs and vs mode is either is rv32 or either 64

--------------------------------------------------------------------------------------------------
*/
/*suffix VS is for variables, reg, wires for VS stage 
suffix G is for variable, reg, wires for G stage 123*/

package ptwalk_rv_hypervisor;

  import Vector::*;
  import FIFOF::*;
  import DReg::*;
  import SpecialFIFOs::*;
  import BRAMCore::*;
  import FIFO::*;
  import GetPut::*;
  import UniqueWrappers::*;
  import resize ::*;

  import dcache_types::*;
  import mmu_types :: * ;
  `include "mmu.defines"
  `include "Logger.bsv"


interface Ifc_ptwalk_rv#(
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
	interface Put#(PTWalk_tlb_request#(xlen)) subifc_from_tlb;
	interface Get#(PTW_response_splitTLB#(xlen, max_varpages, ppnsize, asidwidth, paddr )) subifc_to_tlb;
	/* doc:subifc: to send request to cache */ 
  interface Get#(DMem_request#(xlen, TMul#( `dwords, 8), `desize )) subifc_request_to_cache;// dword 4/8 for rv32/rv64
  /* doc:subifc: to capture response form cache */  
  interface Put#(DMem_core_response#(TMul#(`dwords, 8),`desize `ifdef hypervisor ,paddr `endif )) subifc_response_frm_cache;
  /* doc:subifc: to hold the pending cache to core request */
  interface Put#(DCache_core_request#(xlen, TMul#(`dwords, 8), `desize)) subifc_hold_req; 

endinterface

typedef enum {ReSendReq, WaitForMemory, GeneratePTE, GeneratePTE_S, SwitchPTW } State deriving(Bits,Eq,FShow);
typedef struct{
  Bit#(1)             virt;
  Bit#(TLog#(level))  levels;
} Comparision#(numeric type level) deriving(Bits, Eq, FShow);

/*doc:module: implements page table walk */
  module mkptwalk_rv#(parameter Bit#(32) hartid)(Ifc_ptwalk_rv#(xlen, paddr, max_varpages, ppnsize, lastppnsize, subvpn, page_offset, asidwidth, satp_mode_size, svnapot))
    provisos (/*Bits#(ptwalk_rv_hypervisor::VM_info#(3, ppnsize), a__),
              Add#(b__, asidwidth, xlen)
              Add#(satp_mode_size, c__, xlen)*/
              Add#(a__, TAdd#(ppnsize, page_offset), TAdd#(TSub#(xlen, 10), 12)),
              Add#(b__, asidwidth, xlen),
              Add#(c__, ppnsize, xlen),
              Add#(d__, paddr, TAdd#(ppnsize, page_offset)),
              Add#(e__, TAdd#(subvpn, TSub#(page_offset, subvpn)), paddr),
              Add#(f__, TLog#(max_varpages), TLog#(TMul#(TSub#(max_varpages, 1), subvpn))),
              // Add#(f__, TAdd#(TAdd#(subvpn, 2), TSub#(page_offset, subvpn)), paddr),
              Add#(satp_mode_size, g__, xlen),
              Add#(h__, TMul#(TSub#(max_varpages, 1), subvpn), ppnsize),
              // Bits#(ptwalk_rv_hypervisor::VM_info#(3, ppnsize), h__),
            `ifdef RV64
              Add#(xlen, i__, 74),
            `else
              Add#(xlen, i__, 42),
            `endif
              Add#(j__, paddr, xlen),
              Add#(k__, 4, ppnsize),
              
              // Add#(l__, paddr, TAdd#(ppnsize, subvpn)),
              // Add#(m__, TMul#(TSub#(max_varpages, 1), subvpn), paddr),
              Add#(n__, TAdd#(lastppnsize, TAdd#(TMul#(TSub#(max_varpages, 1), subvpn), 12)), xlen),
              Add#(lastppnsize, o__, ppnsize),
              // Add#(p__, paddr, ppnsize), // TODO: this is wrong correct it
              Add#(q__, TMul#(TSub#(max_varpages, 1), subvpn), xlen)
              );

	  let v_xlen          = valueOf(xlen);
	  let v_paddr         = valueOf(paddr);
	  let v_max_varpages  = valueOf(max_varpages);
    let v_ppnsize       = valueOf(ppnsize);
    let v_lastppnsize   = valueOf(lastppnsize);
	  let v_subvpn        = valueOf(subvpn);
	  let v_page_offset   = valueOf(page_offset);
	  let v_asidwidth     = valueOf(asidwidth);
	  let v_svnapot       = valueOf(svnapot);

	  String ptwalk="";
    
    // typedef PTW_response_splitTLB#(xlen, max_varpages, ppnsize, asidwidth, paddr) Response_TLB;
    // typedef DMem_core_response#(TMul#(`dwords, 8),`desize) Core_response;
    // typedef PTWalk_tlb_request#(xlen) Request_TLB;
     

	  /*doc:fifo: holds request from tlb*/
	  FIFOF#(PTWalk_tlb_request#(xlen)) ff_req_queue <- mkBypassFIFOF();  //from tlb
	  /*doc:fifo: holds the response to tlb */ 
	  FIFOF#(PTW_response_splitTLB#(xlen, max_varpages, ppnsize, asidwidth, paddr)) ff_response <- mkSizedFIFOF(2);   // to tlb
	  /*doc:fifo: hold the request to cache */
	  FIFOF#(DMem_request#(xlen, TMul#( `dwords, 8), `desize )) ff_memory_req <- mkSizedFIFOF(2);   //request to cache
	  /*doc:fifo: hold the response from cache */
	  FIFOF#(DMem_core_response#(TMul#(`dwords, 8),`desize `ifdef hypervisor ,paddr `endif )) ff_memory_response <- mkBypassFIFOF();   // response from cache
	  /*doc:fifo: hold the request of DCahce_core_request type */
	  FIFOF#(DCache_core_request#(xlen, TMul#(`dwords, 8), `desize)) ff_hold_req <- mkSizedFIFOF(2);    // hold request

	  FIFOF#(PTWalk_tlb_request#(xlen)) ff_req_gpa_to_hpa <- mkBypassFIFOF(); // request if enq when we have a gpa and want its translation 
	  FIFOF#(PTWalk_tlb_request#(xlen)) ff_req_of_tra_gva_to_hpa <- mkLFIFOF(); // shadow ff to save the main request of virtual address translation 

    /*doc:reg: this register holds the epoch value */      
    Reg#(Bit#(`desize)) rg_hold_epoch <- mkRegA(0);
    /*doc:reg: register to hold the state */
    Reg#(State) rg_state<- mkRegA(GeneratePTE);
    /*doc:reg: register to hold the virtulization bit "V", used to change the working of the states
    based on the stage1 (V = 0) and stage2 (V=1) */
    Reg#(Bit#(1)) rg_v <- mkRegA(?);
    /*doc:reg: register to hold the Guest Virtual Address*/
    Reg#(Bit#(xlen)) rg_gva <- mkRegA(0);//virtual address could be of 39, 48 ,57 
    /*doc:reg: register to hold the Host Physical Address*/
    Reg#(Bit#(paddr)) rg_hpa <- mkRegA(0);
    /*doc:reg: to hold the levels for G-stage/stage2 translation */
	  Reg#(Bit#(TLog#(max_varpages))) rg_levels_G <- mkRegA(0);	  
    /*doc:reg: to hold the value "a" used in the translation in G-stage*/
    Reg#(Bit#(TAdd#(ppnsize, page_offset))) rg_a_G <- mkRegA(0);
    /*doc:reg: to hold Guest Physical Address*/
    Reg#(Bit#(paddr)) rg_gpa <- mkRegA(0);
    /*doc:reg: to hold the levels for VS-stage/stage1 translation */
    Reg#(Bit#(TLog#(max_varpages))) rg_levels_VS <- mkRegA(0); 
    /*doc:reg: to hold the value "a" used in the translation in VS-stage*/
    Reg#(Bit#(TAdd#(ppnsize, page_offset))) rg_a_VS <- mkRegA(0); 
    /*doc:reg: register tellling if the final translation is going on or not*/
    Reg#(Bool) last_translation <- mkRegA(False);
    /*doc:reg: to tell if the translation is transparent or not */
    Reg#(Bool) trans_translation <- mkRegA(False);
    /*doc:reg: use to tell which page table level you are in similar to i in algo */
    Reg#(Bit#(TLog#(max_varpages))) rg_levels <- mkRegA(0); 
    /*doc:reg: this register is named "a" to keep coherence with the algorithem provided in the spec */
    Reg#(Bit#(TAdd#(ppnsize, page_offset))) rg_a <- mkRegA(0);
  
    /*doc:wire: used to fire deq_holding_fifo rule */
    Wire#(Bool) wr_deq_holding_ff <- mkWire();


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

    /*doc:func: function to generate physical address */
    function Bit#(xlen) fn_gen_phy_address (Gen_add#(xlen, ppnsize, max_varpages) g);
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
    /*wrapper for the fn_gen_phy_address*/
    Wrapper#(Gen_add#(xlen, ppnsize, max_varpages), Bit#(xlen)) gen_phy_address <- mkUniqueWrapper(fn_gen_phy_address);
    
    /*doc:func: function to check permission some wrapper thing to de done  */
    function Bool fn_fault_check( DMem_core_response#(TMul#(`dwords, 8),`desize `ifdef hypervisor ,paddr `endif ) response, 
                                  PTWalk_tlb_request#(xlen) request, 
                                  Comparision#(max_varpages) c );
      // actionvalue
        Bool stage2 = (c.virt == 0)? True: False; // check if this is vs or g mode
        Bool supervisor_req = (request.v == 0)? True: False; //check wheather it is from a supvisor request

        Bool lv_fault             = False;
        
        Bool lv_trap              = False;
        // 10 bit are reserved for permission for all the virtulization scheme
        // capture the permissions of the hit entry from the TLBs
        // 7 6 5 4 3 2 1 0
        // D A G U X W R V
        TLB_permissions lv_permissions=bits_to_permission(truncate(response.word));
        AccessTypes lv_access_types = unpack(request.access);
        // `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Permissions",hartid, fshow(lv_permissions)))
        Bool lv_pte_pbmt          = False;
        Bool lv_pte_n             = False;
        Bool lv_reserve_bit_set   = False;

        if (v_max_varpages > 2) begin
          Bit#(7) _reserve_bits = response.word[60:54];
          lv_reserve_bit_set = _reserve_bits != 0;

          Bit#(2) _pbmt = response.word[62:61];
          Bit#(1) _n = response.word[63];
          lv_pte_pbmt = _pbmt!= 0;
          lv_pte_n = _n!= 0;
        end

        Bit#(TSub#(xlen, 10)) _pte = truncateLSB(response.word);
        // from spec: if the requested memory access is allowed by the pte.r, pte.w, pte.x, and 
        // pte.u bits, given the current privilege mode and the value of the SUM and MXR fields of 
        // the mstatus register. If not, stop and raise a page-fault exception
        Bool _c = (lv_permissions.u) ? ((request.priv == 'b01) && (lv_access_types == Fetch || !unpack(request.sum))) : (request.priv != 'b01);
        Bool _d = lv_access_types == Fetch ? !(lv_permissions.x) :
                  lv_access_types == Load  ? !(lv_permissions.r) && !(unpack(request.mxr) && (lv_permissions.x)) :
                                            !((lv_permissions.r) && (lv_permissions.w));
        // from spec: if any bits or encodings that are reserved for future standard use are set 
        // within pte, stop and raise a page-fault exception
        if (lv_reserve_bit_set) begin // check is any of the reserved bits are set
          lv_fault=True;
          // `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - Reserved Bits Set",hartid))
        end
        else if(lv_pte_n && valueOf(svnapot)==1) begin
          if(!fn_napot_bits_check(_pte)) begin
            lv_fault = True;
            // `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - NAPOT Bits Check Failed",hartid))
          end
        end
        // from spec: For non-leaf PTEs, the D, A, and U bits are reserved for future standard use. Until their 
        // use is defined by a standard extension, they must be cleared by software for forward 
        // compatibility.
        else if(!lv_permissions.x && !lv_permissions.w && !lv_permissions.r && lv_permissions.v ) begin//next level page 
          if(lv_permissions.d || lv_permissions.a || lv_permissions.u || lv_pte_n || lv_pte_pbmt) begin
            lv_fault=True;
            // `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - Next Level PTW has D|A|U|N|PBMT set",hartid))
          end
        end
        else if (stage2 && !supervisor_req && !lv_permissions.u)begin //only G-stage check
          lv_fault=True;
          // `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - User permissions Failed",hartid))
        end
        else if ((!stage2 || supervisor_req) && _c ) begin // only VS(v==1) || S - stage check
          lv_fault=True;
          // `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - User permissions Failed",hartid))
        end
        // from spec: If pte.v = 0, or if pte.r = 0 and pte.w = 1 stop and raise a page-fault exception
        else if (!lv_permissions.v || (!lv_permissions.r && lv_permissions.w)) begin
          lv_fault=True;
          // `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - Valid not Set or Reserved RW settings",hartid))
        end
        else if (_d) begin
          lv_fault=True;
          // `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - Access permissions failed",hartid))
        end
        // from spec: A superpage must be virtually and physically aligned a page-fault exception is 
        // raised if the physical address is insufficiently aligned.
        else if(fn_ppn_comparision(_pte, c.levels) && c.levels !=0 ) begin // mis-allign check
          lv_fault=True;
          // `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - Mis Aligned Page",hartid))
        end
        // form spec: When a virtual page is accessed and the A bit is clear, or is written and 
        // the D bit is clear, a page-fault exception is raised.
        else if (!lv_permissions.a || 
                ((lv_access_types == Store || lv_access_types == Atomic) && !lv_permissions.d)) begin
          lv_fault = True;
          // `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Fault Reason - A|D bits not set",hartid))
        end

        return lv_fault;
      // endactionvalue

    endfunction:fn_fault_check

    Wrapper3#(DMem_core_response#(TMul#(`dwords, 8),`desize `ifdef hypervisor ,paddr `endif ), PTWalk_tlb_request#(xlen), Comparision#(max_varpages), Bool) fault_check <- mkUniqueWrapper3(fn_fault_check);

    /*doc:func: function to gen dcache packet*/
    function DMem_request#(xlen, TMul#( `dwords, 8), `desize ) fn_gen_dcache_packet (Bit#(xlen) address, 
                                                   Bool lv_reqtype, Bool lv_trap, Bit#(`causesize) lv_cause, Bit#(2) priv,
                                                   Bit#(1) mxr, Bit#(1) sum, Bit#(xlen) satp);
      return DMem_request{address     : address,
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
                        `ifdef hypervisor 
                          hfence      : False,
                        `endif
                          sfence_req  : SfenceReq{sfence: False},
                          ptwalk_req  : lv_reqtype,
                          ptwalk_trap : lv_trap};
    endfunction
  
    /*doc:func: function to decode the info embedded status csr for different stage*/
    function VM_info#(TLog#(max_varpages), ppnsize) fn_vm_info_decode (PTWalk_tlb_request#(xlen) request);
      Bool stage2 = (rg_v == 0)? True: False; // check if this is vs or g mode
      VM_info#(TLog#(max_varpages), ppnsize) _vminfo = unpack(0);
      Bit#(satp_mode_size) atp_mode = (stage2)?truncateLSB(request.hgatp):truncateLSB(request.vssatp);
      Bit#(ppnsize) root_ppn = (stage2)?truncateLSB(request.hgatp):truncateLSB(request.vssatp);
      Bit#(TLog#(max_varpages)) levels = (v_max_varpages==2 && atp_mode == 1)? 1: 
                                          (v_max_varpages >=3 && atp_mode==8)?2:
                                          (v_max_varpages >=4 && atp_mode==9)?3:
                                          (v_max_varpages ==5 && atp_mode==10)?4:
                                          0;
      _vminfo.widenbits = (stage2)? 2: 0;  
      _vminfo.ppn = root_ppn;
      _vminfo.levels = levels;
      return _vminfo; 
    endfunction 

    
    /*doc:func: to get the subvpn seggrated out based on the level of translation */
    function Bit#(subvpn) fn_get_vpn_acc_to_level (Bit#(xlen) address, Bit#(TLog#(max_varpages)) levels);
      Bit#(subvpn) lv_vpn[v_max_varpages];
      for(Integer i = 0;i < v_max_varpages; i= i+1) begin  
        lv_vpn[i] = address[(i+1)* v_subvpn + v_page_offset -1 : i*v_subvpn + v_page_offset];
      end
      return lv_vpn[levels];
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
        if(lv_request.v ==0)
          rg_state<=GeneratePTE_S;
        else
          rg_state<=GeneratePTE;
      wr_deq_holding_ff <= True;
    endrule

    /*doc:rule: rule to dequeue from ff_hold_req */
    rule rl_deq_holding_fifo(wr_deq_holding_ff);
      ff_hold_req.deq;
    endrule
    /*doc:rule: rule to generate PTE for supervisor request */
    rule rl_generate_pte_s(rg_state==GeneratePTE_S);
      let lv_request = ff_req_queue.first;
      `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Recieved(S) Request: ",hartid,fshow(ff_req_queue.first)))

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

      `logLevel( ptwalk, 2, $format("[%2d]PTWALK(S): Sending PTE - Address to DMEM:%h",hartid,lv_pte_address))
      ff_memory_req.enq(fn_gen_dcache_packet(lv_request.address, True, False,?, lv_request.priv,lv_request.mxr,lv_request.sum, lv_request.satp));
      rg_state<=WaitForMemory;
    endrule
    
    /*doc:rule: it is responsible for geration the address for a PTE both in VS mode and HS mode
    the address of PTE in VS mode is GPA and the address HS mode is HPA(host physical address)*/
    rule rl_generate_pte(rg_state==GeneratePTE);
      let request = ff_req_queue.first;
      // Bool isHXLEN32 = (v_xlen ==32)? True:False;
      Bool stage2 = (rg_v == 0)? True: False; // check if this is vs or g mode
      VM_info#(TLog#(max_varpages), ppnsize) info = fn_vm_info_decode(request);
      let levels = (stage2)?rg_levels_G: rg_levels_VS;
      //check for transparent translation 
      Bool transparent_translation = (info.levels == 0 )? True: False;
      //if transparent translation 
      if(transparent_translation)begin
        if(!stage2) begin
          `logLevel(ptwalk , 2, $format("[%2d]PTWALK: Recieved GVA in VS-Stage(transparent tran)", hartid, fshow(ff_req_queue.first)))
          rg_gpa <= truncate(request.address); // copy the gva as there is no translation of gva
          last_translation <= True; // set the flag as we got the final GPA in vs-stage now we have translate to hpa
          rg_state <= SwitchPTW;
        end
         
      end
      else begin // not a transparent translation 
        if (rg_v ==1) 
          `logLevel(ptwalk , 2, $format("[%2d]PTWALK: Recieved GVA in VS-Stage(not transparent tran)", hartid, fshow(ff_req_queue.first)))
        else
          `logLevel(ptwalk , 2, $format("[%2d]PTWALK: Recieved GVA in G-Stage(not transparent tran)", hartid, fshow(ff_req_queue.first)))

        //create the vpn upon request using the level value it is requested and the subvpn value
        //assign the value to rg_a_VS
        let vpn = (!stage2)? fn_get_vpn_acc_to_level(rg_gva, levels) : fn_get_vpn_acc_to_level(zeroExtend(rg_gpa), levels);// last level problem 2 extra bits
        Bit#(TAdd#(subvpn, 2)) vpn_stage2 = {2'b0, vpn};// this should not be 00 it should change according to the address
        Bit#(ppnsize) ppn = info.ppn;// ppn from the CSR vssatp /hgatp
        let max_level = info.levels;
        Bit#(TAdd#(ppnsize, page_offset)) a = (levels == max_level)? {ppn, 'd0} : (stage2)? rg_a_G: rg_a_VS;//80_000
        Bit#(paddr) _a = truncate(a);
        Bit#(TSub#(page_offset, subvpn)) _app_zero = 0;
        //80_000_000; 90_000_010; 90_001_000; 90_002_000; 90 000 010;  
        // if stage 1 then add gva in place of vpn 
        Bit#(paddr) pte_address = _a + (zeroExtend({vpn, _app_zero}));// this is added just for understanding if not added it will remain same
                                                                                                                                           // same as the address is zero extended so it doesn't matter if prefixed with 2'b0
        
        if(stage2)begin
          // `logLevel(ptwalk , 2, $format("[%2d]PTWALK: Translated GPA to HPA:%h)", hartid, pte_address)) 
          ff_memory_req.enq(fn_gen_dcache_packet(zeroExtend(pte_address), True, False,?, request.priv,request.mxr,request.sum, request.hgatp));
          rg_hpa <= pte_address;
          rg_state <= WaitForMemory;
        end
        else begin
          // `logLevel(ptwalk , 2, $format("[%2d]PTWALK: Translated GVA to GPA:%h)", hartid, pte_address)) 
          rg_gpa <= pte_address;
          rg_state <= SwitchPTW;
        end 
        
      end
  
    endrule: rl_generate_pte

    /*doc:rule: rule to toggle the working between stage 1 and stage 2*/
    rule rl_switch_ptw (rg_state==SwitchPTW);
      let request = ff_req_queue.first;
      Bool stage2 = (rg_v == 0)? True: False; // check if this is vs or g mode
      if(!stage2)begin//switch request is from vs mode
        ff_req_of_tra_gva_to_hpa.enq(request);
        rg_v <= 0;
        Bit#(satp_mode_size) hgatp_mode = truncateLSB(request.hgatp);//stage 2 csr
        Bit#(TLog#(max_varpages)) levels = (v_max_varpages==2 && hgatp_mode == 1)? 1: 
                                          (v_max_varpages >=3 && hgatp_mode==8)?2:
                                          (v_max_varpages >=4 && hgatp_mode==9)?3:
                                          (v_max_varpages ==5 && hgatp_mode==10)?4:
                                            rg_levels_G;
        `logLevel( ptwalk, 0, $format("[%2d]PTWALK: rg_levels_G:%d",hartid, levels))
        rg_levels_G <= levels; 
        rg_state <= GeneratePTE;        
      end
      else begin //not edited
        rg_v <= 1;
        //70 000 000; 70 001 000; 70 002 000
        ff_memory_req.enq(fn_gen_dcache_packet(zeroExtend(rg_hpa), True, False,?, request.priv,request.mxr,request.sum, request.satp));
        rg_state <= WaitForMemory;
      end
    endrule:rl_switch_ptw

    /*doc:rule: rule to do the checks on the PTE and send the response with the translated address or with a fault  */
    rule rl_check_pte (rg_state == WaitForMemory);
      let request = ff_req_queue.first;
      Bool stage2 = (rg_v == 0)? True: False; // check if this is vs or g mode
      Bool supervisor_req = (request.v == 0)? True: False; //check wheather it is from a supvisor request
      
      let response = ff_memory_response.first();
      ff_memory_response.deq;
      `logLevel( ptwalk, 2, $format("[%2d]PTWALK: For Request: ",hartid,fshow(ff_req_queue.first)))
      `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Memory Response: ",hartid,fshow(ff_memory_response.first)))
      Bit#(`causesize) lv_cause=0;
      Bool lv_trap=False;
      // 10 bit are reserved for permission for all the virtulization scheme
      // capture the permissions of the hit entry from the TLBs
      // 7 6 5 4 3 2 1 0
      // D A G U X W R V
      TLB_permissions lv_permissions=bits_to_permission(truncate(response.word));
      AccessTypes lv_access_types = unpack(request.access);
  
      Bool lv_pte_pbmt = False;
      Bool lv_pte_n = False;
      Bool lv_reserve_bit_set = False;

      if (v_max_varpages > 2) begin
        Bit#(7) _reserve_bits = response.word[60:54];
        lv_reserve_bit_set = _reserve_bits != 0;

        Bit#(2) _pbmt = response.word[62:61];
        Bit#(1) _n = response.word[63];
        lv_pte_pbmt = _pbmt!= 0;
        lv_pte_n = _n!= 0;
      end
      Bit#(TSub#(xlen, 10)) _pte = truncateLSB(response.word);
      // the condition below will be true for 
      // hypervisor enabled core having a supervisor request
      // nothing else
      if(supervisor_req)begin//TODO:this will not enter for VSSATP != 0 and  HGATP == 0
              
        // vpn segregation 
        Bit#(subvpn) lv_vpn[v_max_varpages];
        for(Integer i = 0;i < v_max_varpages; i= i+1) begin  
          lv_vpn[i] = request.address[(i+1)* v_subvpn + v_page_offset -1 : i*v_subvpn + v_page_offset];
        end
        
        // Fault or trap cheking logic Start
        let c = Comparision{virt    : 0,
                            levels  : rg_levels};
        
        let lv_fault <- fault_check.func(response, request, c);
  
        // Fault or trap cheking logic End  
        
        if(lv_fault || response.trap) begin  
          lv_trap=True;
          if(response.trap)begin
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
            ff_memory_req.enq(fn_gen_dcache_packet(request.address, False, True, lv_cause, request.priv,
                                                    request.mxr, request.sum, request.satp));
          Bit#(asidwidth) satp_asid = truncate(request.satp >> v_ppnsize);
          Bit#(4) napot_repl = lv_vpn[0][3:0];//replace napot_bits from ppn0 with the napot_bits of VPN
          Bit#(ppnsize) ppn = (rg_levels == 0 && lv_pte_n && valueOf(svnapot)==1 && fn_napot_bits_check(_pte) && lv_pte_n)? {response.word[v_ppnsize +9:14], napot_repl} : response.word[v_ppnsize +9:10]; 
          ff_response.enq(PTW_response_splitTLB{va          : request.address, 
                                                asid        : satp_asid,
                                                ppn         : ppn, 
                                                permissions : lv_permissions,
                                                trap        : lv_trap,
                                                cause       : lv_cause,
                                                levels      : rg_levels,
                                                n           : (fromInteger(v_svnapot) & pack(lv_pte_n) & pack(fn_napot_bits_check(_pte))),
                                                hgatp       : request.hgatp,
                                                vssatp      : request.vssatp,
                                                levels_G    : 0,
                                                levels_VS   : ?,
                                                gva         : truncate(request.address),
                                                gpa         : resize(ppn),
                                                gpa_perm    : lv_permissions,
                                                hpa         : resize(ppn),
                                                hpa_perm    : lv_permissions
                                                });
          if(lv_access_types != Fetch)
            wr_deq_holding_ff <= True;
          ff_req_queue.deq();
          rg_state<=GeneratePTE_S;
        end
        else if (!lv_permissions.r && !lv_permissions.x)begin // this pointer to next level
          rg_levels<=rg_levels-1;

          
          Bit#(TSub#(xlen, 10)) _response = truncateLSB(response.word);
          rg_a<=truncate({_response,12'b0});// will truncate to fit the ppn size

          rg_state<=GeneratePTE_S;
          `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Pointer to NextLevel:%h Levels:%d",hartid, {response.word[31 : 10], 12'b0}, 
                                        rg_levels))
        end
        else begin // Leaf PTE found
          Bit#(asidwidth) satp_asid = truncate(request.satp >> v_ppnsize);
          Bit#(4) napot_repl = lv_vpn[0][3:0];//replace napot_bits from ppn0 with the napot_bits of VPN
          Bit#(ppnsize) ppn = (rg_levels == 0 && lv_pte_n && valueOf(svnapot)==1 && fn_napot_bits_check(_pte) && lv_pte_n)? {response.word[v_ppnsize +9:14], napot_repl} : response.word[v_ppnsize +9:10]; 
          ff_response.enq(PTW_response_splitTLB{va          : request.address, 
                                                asid        : satp_asid,
                                                ppn         : ppn, 
                                                permissions : lv_permissions,
                                                trap        : lv_trap,
                                                cause       : lv_cause,
                                                levels      : rg_levels,
                                                n           : (fromInteger(v_svnapot) & pack(lv_pte_n) & pack(fn_napot_bits_check(_pte))),
                                                hgatp       : request.hgatp,
                                                vssatp      : request.vssatp,
                                                levels_G    : 0,
                                                levels_VS   : ?,
                                                 gva         : truncate(request.address),
                                                gpa         : resize(ppn),
                                                gpa_perm    : lv_permissions,
                                                hpa         : resize(ppn),
                                                hpa_perm    : lv_permissions
                                                });
          `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Found Leaf PTE:%h levels: %d",hartid, response.word,
                                        rg_levels))
          
          if(lv_access_types != Fetch)
            rg_state<=ReSendReq;
          else begin
            rg_state<=GeneratePTE_S;
            ff_req_queue.deq;
          end
          
        end 
      end
      
      else if(stage2 && !supervisor_req) begin
        `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Permissions from G-stage",hartid, fshow(lv_permissions)))
        
        let c = Comparision{virt    : rg_v, //0
                            levels  : rg_levels_G};
        let lv_fault <- fault_check.func(response, request, c); 
        // Fault or trap cheking logic End  
        
        if(lv_fault || response.trap) begin  
          lv_trap=True;
          if(response.trap)begin
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
          
          `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Generated Error in G-stage translation. Cause:%d",hartid,lv_cause))
          
          // correct for G-stage translation 
          if(lv_access_types != Fetch)
            ff_memory_req.enq(fn_gen_dcache_packet(request.address, False, True, lv_cause, request.priv,
                                                    request.mxr, request.sum, request.satp));
          Bit#(asidwidth) satp_asid = truncate(request.satp >> v_ppnsize);
          let lv_vpn = fn_get_vpn_acc_to_level(request.address, 0);
          Bit#(4) napot_repl = lv_vpn[3:0];//replace napot_bits from ppn0 with the napot_bits of VPN
          Bit#(ppnsize) ppn = (rg_levels_G == 0 && lv_pte_n && valueOf(svnapot)==1 && fn_napot_bits_check(_pte) && lv_pte_n)? {response.word[v_ppnsize +9:14], napot_repl} : response.word[v_ppnsize +9:10]; 
          /*TODO:can add the function to properly mix the vpn and ppn from the pte but since this 
                 comes under an trap or fault response therefore no importance will be given to hpa 
                 so we can get away with it*/
          ff_response.enq(PTW_response_splitTLB{va          : request.address,
                                                cause       : lv_cause,
                                                trap        : lv_trap,
                                                n           : (fromInteger(v_svnapot) & pack(lv_pte_n) & pack(fn_napot_bits_check(_pte))),
                                              `ifndef hypervisor
                                                asid        : satp_asid,
                                                ppn         : ppn,
                                                permissions : lv_permissions                                            
                                              `else
                                                hgatp       : request.hgatp,
                                                vssatp      : request.vssatp,
                                                levels_G    : rg_levels_G,
                                                levels_VS   : rg_levels_VS,
                                                gva         : rg_gva,
                                                gpa         : rg_gpa,
                                                gpa_perm    : ?,
                                                hpa         : rg_hpa,
                                                hpa_perm    : lv_permissions
                                              `endif
                                              });
          if(lv_access_types != Fetch)
            wr_deq_holding_ff <= True;
          ff_req_queue.deq();
          rg_state<=GeneratePTE;
        end
        else if (!lv_permissions.r && !lv_permissions.x)begin // this pointer to next level
          rg_levels_G <= rg_levels_G - 1;

          // 10 bits from the LSB are used for permission
          // 10 bits from MSB are for SVNAOPT and some are reserved
          Bit#(TSub#(xlen, 10)) _response = truncateLSB(response.word);
          rg_a_G <= truncate({_response,12'b0});// will truncate to fit the ppn size

          rg_state<=GeneratePTE;
          `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Pointer to NextLevel G-stage :%h Levels:%d",hartid, {response.word[31 : 10], 12'b0}, 
                                        rg_levels_G))
        end
        else begin // Leaf PTE found
          Bit#(asidwidth) satp_asid = truncate(request.satp >> v_ppnsize);
          let lv_vpn = fn_get_vpn_acc_to_level(request.address, 0);
          Bit#(4) napot_repl = lv_vpn[3:0];//replace napot_bits from ppn0 with the napot_bits of VPN
          Bit#(ppnsize) ppn = (rg_levels_G == 0 && lv_pte_n && valueOf(svnapot)==1 && fn_napot_bits_check(_pte) && lv_pte_n)? {response.word[v_ppnsize +9:14], napot_repl} : response.word[v_ppnsize +9:10]; 
          
          //using wrapper function for generating physical addres using gpa, ppn, levels_G
          // let m = Gen_add{addr    : rg_gpa,
          //                 ppn     : ppn, 
          //                 levels  : rg_levels_G,
          //                 n       : lv_pte_n};
                  
          // let physicaladdress <- gen_phy_address.func(m);
          
          // rg_hpa <= truncate(physicaladdress);// TODO:make correction to make proper mixture of ppn and vpn --DONE
          rg_hpa <= resize(ppn);
          if(last_translation)begin
            // translation_done <= True;
            if(lv_access_types != Fetch)// 3: Fetch
                rg_state<=ReSendReq;
            else begin
              rg_state<=GeneratePTE;
              ff_req_queue.deq;
            end
            ff_response.enq(PTW_response_splitTLB{va          : request.address,//GVA
                                                  cause       : lv_cause,
                                                  trap        : lv_trap,
                                                  n           : ?/*(fromInteger(v_svnapot) & pack(lv_pte_n) & pack(fn_napot_bits_check(_pte)))*/,
                                                `ifndef hypervisor
                                                  asid        : ?,
                                                  ppn         : ppn,
                                                  permissions : ?                                            
                                                `else
                                                  hgatp       : request.hgatp,
                                                  vssatp      : request.vssatp,
                                                  levels_G    : rg_levels_G,
                                                  levels_VS   : rg_levels_VS,
                                                  gva         : rg_gva,
                                                  gpa         : rg_gpa,
                                                  gpa_perm    : ?,
                                                  hpa         : rg_hpa,// TODO :RIGHT IS SENDING 
                                                  hpa_perm    : lv_permissions
                                                `endif
                                                });
            last_translation <= False; 
            `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Final Translation  virtual addr:%h translated addr: %h levels: %d",hartid, rg_gva, rg_hpa,
                                        rg_levels_G))                                   
            // rg_state <= TranslationDone;
          end
          else begin
            rg_state <= SwitchPTW;
          end 
          `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Found Leaf PTE in G-stage :%h levels: %d",hartid, response.word,
                                        rg_levels_G))
                    
        end
      end
      else if (!stage2 && !supervisor_req) begin//stage 1 permission checking
        // Fault or trap cheking logic Start
        `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Permissions from VS-stage",hartid, fshow(lv_permissions)))
        
        let c = Comparision{virt    : rg_v,//1
                            levels  : rg_levels_VS};
        let lv_fault <- fault_check.func(response, request, c); 
        // Fault or trap cheking logic End  
        
        if(lv_fault || response.trap) begin  
          lv_trap=True;
          if(response.trap)begin
            case(lv_access_types) matches
              Fetch:  lv_cause = `Inst_access_fault;  // Fetch
              Load:   lv_cause = `Load_access_fault;  // Load
              default:lv_cause = `Store_access_fault; // Atomic
            endcase
          end
            
          else if(lv_fault)begin
            case(lv_access_types) matches
              Fetch:  lv_cause = `Inst_guest_pagefault;  // Fetch
              Load:   lv_cause = `Load_guest_pagefault;  // Load
              default:lv_cause = `Store_guest_pagefault; // Atomic
            endcase
          end
          
          `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Generated Error. Cause:%d",hartid,lv_cause))
          
          // correct for VS-stage translation 
          if(lv_access_types != Fetch)
            ff_memory_req.enq(fn_gen_dcache_packet(request.address, False, True, lv_cause, request.priv,
                                                    request.mxr, request.sum, request.satp));
          Bit#(asidwidth) satp_asid = truncate(request.satp >> v_ppnsize);
          let lv_vpn = fn_get_vpn_acc_to_level(request.address, 0);
          Bit#(4) napot_repl = lv_vpn[3:0];//replace napot_bits from ppn0 with the napot_bits of VPN
          Bit#(ppnsize) ppn = (rg_levels_VS == 0 && lv_pte_n && valueOf(svnapot)==1 && fn_napot_bits_check(_pte) && lv_pte_n)? {response.word[v_ppnsize +9:14], napot_repl} : response.word[v_ppnsize +9:10]; 
          ff_response.enq(PTW_response_splitTLB{va          : request.address,
                                                cause       : lv_cause,
                                                trap        : lv_trap,
                                                n           : (fromInteger(v_svnapot) & pack(lv_pte_n) & pack(fn_napot_bits_check(_pte))),
                                              `ifndef hypervisor
                                                asid        : satp_asid,
                                                ppn         : ppn,
                                                permissions : lv_permissions                                            
                                              `else
                                                hgatp       : request.hgatp,
                                                vssatp      : request.vssatp,
                                                levels_G    : rg_levels_G,
                                                levels_VS   : rg_levels_VS,
                                                gva         : rg_gva,
                                                gpa         : rg_gpa,
                                                gpa_perm    : ?,
                                                hpa         : rg_hpa,
                                                hpa_perm    : lv_permissions
                                              `endif
                                              });
          if(lv_access_types != Fetch)
            wr_deq_holding_ff <= True;
          ff_req_queue.deq();
          rg_state<=GeneratePTE;
        end
        else if (!lv_permissions.r && !lv_permissions.x)begin // this pointer to next level
          rg_levels_VS <= rg_levels_VS - 1;

          // 10 bits from the LSB are used for permission
          // 10 bits from MSB are for SVNAOPT and some are reserved
          Bit#(TSub#(xlen, 10)) _response = truncateLSB(response.word);
          rg_a_VS <= truncate({_response,12'b0});// will truncate to fit the ppn size

          rg_state<=GeneratePTE;
          `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Pointer to NextLevel:%h Levels:%d",hartid, {response.word[31 : 10], 12'b0}, 
                                        rg_levels_VS))
        end
        else begin // Leaf PTE found
          Bit#(asidwidth) satp_asid = truncate(request.satp >> v_ppnsize);
          let lv_vpn = fn_get_vpn_acc_to_level(request.address, 0);
          Bit#(4) napot_repl = lv_vpn[3:0];//replace napot_bits from ppn0 with the napot_bits of VPN
          Bit#(ppnsize) ppn = (rg_levels_VS == 0 && lv_pte_n && valueOf(svnapot)==1 && fn_napot_bits_check(_pte) && lv_pte_n)? {response.word[v_ppnsize +9:14], napot_repl} : response.word[v_ppnsize +9:10]; 
          
          //using wrapper function for generating physical addres using gva, ppn, levels_VS
          let m = Gen_add{addr   : rg_gva,
                          ppn    : ppn, 
                          levels : rg_levels_VS,
                          n      : lv_pte_n};
                  
          let physicaladdress <- gen_phy_address.func(m);

          rg_gpa <= truncate(physicaladdress);
          last_translation <= True;
          rg_state <= SwitchPTW;
          
          `logLevel( ptwalk, 2, $format("[%2d]PTWALK: Found Leaf PTE VS-stage:%h levels: %d",hartid, response.word,
                                        rg_levels_VS))
                    
        end
      end
    endrule: rl_check_pte

     interface subifc_from_tlb            = interface Put
      /* doc:method: to set level register according to satp mode */
      method Action put(PTWalk_tlb_request#(xlen) a);
        `logLevel( ptwalk, 0, $format("[%2d]PTWALK: Got new request:",hartid, fshow(a)))
        // ff_req_queue.enq(a);
        if(a.v == 0)begin
          //when hypervisor is enabled but need only one level of translation 
          Bit#(satp_mode_size) curr_satp_mode = truncateLSB(a.satp);
          let lv_levels = (v_max_varpages==2 && curr_satp_mode == 1)? 1: 
                      (v_max_varpages >=3 && curr_satp_mode==8)?2:
                      (v_max_varpages >=4 && curr_satp_mode==9)?3:
                      (v_max_varpages ==5 && curr_satp_mode==10)?4:
                      rg_levels;
          `logLevel( ptwalk, 0, $format("[%2d]PTWALK: two-level translation disabled rg_levels:%d",hartid, lv_levels))
          rg_levels <= lv_levels;
          rg_state <= GeneratePTE_S;
        end
        else begin
          // for two level tranlation 
          Bit#(satp_mode_size) vssatp_mode = truncateLSB(a.vssatp); // will contain value from vs csr
          Bit#(satp_mode_size) hgatp_mode = truncateLSB(a.hgatp);
          let lv_levels = (v_max_varpages==2 && vssatp_mode == 1)? 1: 
                      (v_max_varpages >=3 && vssatp_mode==8)?2:
                      (v_max_varpages >=4 && vssatp_mode==9)?3:
                      (v_max_varpages ==5 && vssatp_mode==10)?4:
                      rg_levels_VS;
          rg_levels_VS <= lv_levels;        
          rg_gva <= a.address;       
          rg_v <= a.v;
          if( vssatp_mode != 0 && hgatp_mode == 0 ) begin // one level page table walk but with vssatp governing it
            a.satp = a.vssatp;
            let levels = (v_max_varpages==2 && vssatp_mode == 1)? 1: 
                      (v_max_varpages >=3 && vssatp_mode==8)?2:
                      (v_max_varpages >=4 && vssatp_mode==9)?3:
                      (v_max_varpages ==5 && vssatp_mode==10)?4:
                      rg_levels;
            rg_levels <= levels;
            rg_state <= GeneratePTE_S;
          end 
          else 
            rg_state <= GeneratePTE;

        `logLevel( ptwalk, 0, $format("[%2d]PTWALK: two-level translation enabled rg_levels_VS:%d",hartid, lv_levels))
        end
        ff_req_queue.enq(a);
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
endpackage : ptwalk_rv_hypervisor
