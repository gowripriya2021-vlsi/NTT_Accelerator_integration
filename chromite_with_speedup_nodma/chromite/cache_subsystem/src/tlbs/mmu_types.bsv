/* 
see LICENSE.incore
see LICENSE.iitm

Author: Neel Gala, Shubham Roy
Email id: [shubham.roy, neelgala]@incoresemi.com
Details: mmu types [TLB, PTW]

--------------------------------------------------------------------------------------------------
*/ 
package mmu_types;
  `include "Logger.bsv"
`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import FIFO :: * ;
  import FIFOF :: * ;
  import SpecialFIFOs :: * ;
  import DefaultValue   :: * ;
  import Vector::*;

// --------------------------------- Instruction TLB types -----------------------------------//
  typedef struct{
    Bit#(addr)        address;
    Bool              trap;
    Bit#(`causesize)  cause;
  `ifdef hypervisor 
    Bit#(addr)        gpa; //paddr
  `endif
  } ITLB_core_response# (numeric type addr) deriving(Bits, Eq, FShow);
// --------------------------------------------------------------------------------------------//
// --------------------------------- Data TLB types ---------------------------------------------//
  typedef struct{
    Bit#(addr)        address;
    Bool              trap;
    Bit#(`causesize)  cause;
    Bool              tlbmiss;
  `ifdef hypervisor 
    Bit#(addr)        gpa; //paddr
  `endif  
  } DTLB_core_response# (numeric type addr) deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(addr)                    address;
    Bit#(2)                       access;
    Bit#(`causesize)              cause;
    Bool                          ptwalk_trap;
    Bool                          ptwalk_req;
    Bit#(2)                       priv;
    Bit#(1)                       mxr;
    Bit#(1)                       sum;
    Bit#(addr)                    satp;
    SfenceReq#(addr, asidwidth)   sfence_req;
  `ifdef hypervisor
    Bit#(1)                       v; 
    Bit#(addr)                    hgatp;
    Bit#(addr)                    vssatp;
  `endif
  } TLB_core_request# (numeric type addr, numeric type asidwidth) deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(addr)          ppn;
    TLB_permissions     permissions;
    Bool                tlb_hit;
  } SplitTLB_response# (numeric type addr) deriving(Bits, Eq, FShow);

`ifdef hypervisor
  typedef struct{
    Bit#(addr)          ppn;
    TLB_permissions     gpa_permissions;
    TLB_permissions     hpa_permissions;
    Bit#(addr)          hpa;
    Bit#(paddr)         gpa; 
    Bool                tlb_hit;
  } SplitTLB_responseH# (numeric type addr, numeric type paddr) deriving(Bits, Eq, FShow);
`endif

  typedef struct{
    Bool                sfence;
  `ifndef simpl_sfence
    Bit#(addr)          rs1;
    Bit#(asidwidth)     rs2;
    Bit#(5)             rs1addr;
    Bit#(5)             rs2addr;
  `endif
  } SfenceReq#(numeric type addr, numeric type asidwidth) deriving(Bits, FShow, Eq);

  instance DefaultValue #(SfenceReq#(addr, asidwidth));
    defaultValue = SfenceReq{sfence: False
                          `ifndef simpl_sfence ,rs1:0, rs2:0, rs1addr:?, rs2addr:? `endif } ;
  endinstance
// --------------------------------------------------------------------------------------------- //
// --------------------------------- Fully Associative Data TLB types ----------------------------//
  
  typedef struct{
   TLB_permissions                          permissions;
   Bit#(vpnsize)                            vpn;
   Bit#(asidwidth)                          asid;
   Bit#(TMul#(TSub#(varpages,1), subvpn))   pagemask;
   Bit#(ppnsize)                            ppn;
 } VPNTag#(numeric type vpnsize, numeric type asidwidth, numeric type varpages, numeric type subvpn, numeric type ppnsize) deriving(Bits, FShow, Eq);

`ifdef hypervisor
  typedef struct{
    Bit#(vpnsize)                           vpn;//gva
    Bit#(paddr)                             gpa;
    TLB_permissions                         gpa_permissions;
    Bit#(paddr)                             hpa;
    Bit#(ppnsize)                           ppn;
    TLB_permissions                         hpa_permissions;
    Bit#(vmidwidth)                         vmid; // for v=0 vmid is asid for v=1 its hgatp.vmid 
    Bit#(asidwidth)                         asid; // for v=0 this will be ssatp.asid for v=1 its vssatp.asid
    Bit#(TMul#(TSub#(varpages,1), subvpn))  pagemask;
    Bit#(1)                                 v;
} VPNTagH#(numeric type vpnsize, numeric type paddr, numeric type asidwidth, numeric type vmidwidth, numeric type ppnsize, numeric type varpages, numeric type subvpn) deriving(Bits, FShow, Eq);
`endif

 typedef struct{
   Bool               trap;
   Bit#(`causesize)   cause;
   Bool               tlbmiss;
   Bool               translation_done;
   Bit#(addr)         va;
   t                  pte;
   Bit#(2)            access;
   Bit#(2)            priv;
   Bit#(1)            mxr;
   Bit#(1)            sum;
   Bit#(addr)         satp;
`ifdef hypervisor 
  Bit#(1)             v; 
  Bit#(addr)          hgatp;
  Bit#(addr)          vssatp;
`endif 
 } LookUpResult#(type t, numeric type addr) deriving(Bits, FShow, Eq);
// --------------------------------------------------------------------------------------------- //
// --------------------------------- Page Sizes types -----------------------------------//
  typedef enum{
    KB_4
    ,KB_64
    ,MB_2
    ,GB_1
  `ifdef sv32
    ,MB_4
  `endif  
  `ifdef sv48
    ,GB_512
  `endif
  `ifdef sv57
    ,GB_512
    ,TB_256
  `endif
    
  } Page_size deriving(Bits, Eq, FShow);
// --------------------------------------------------------------------------------------------- //

// --------------------------------- PTwalk access types -----------------------------------//
  typedef enum {
    Load   =0, 
    Store  =1, 
    Atomic =2, 
    Fetch  =3
  } AccessTypes deriving(Eq, Bits);
// --------------------------------- PTwalk types -----------------------------------//
  typedef struct{
    Bit#(addr)        address;
    Bit#(2)           access;
    Bit#(2)           priv;
    Bit#(1)           mxr;
    Bit#(1)           sum;
    Bit#(addr)        satp;
  `ifdef hypervisor 
    Bit#(1)           v; 
    Bit#(addr)        hgatp;
    Bit#(addr)        vssatp;
  `endif  
  } PTWalk_tlb_request# (numeric type addr) deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(addr)          va;
    Bit#(`causesize)    cause;
    Bit#(TLog#(level))  levels;
    Bool                trap;// page fault
    Bit#(1)             n;// to indicate whether this is a napot PTE
    Bit#(asidwidth)     asid;
    Bit#(ppnsize)       ppn;	
    TLB_permissions     permissions;
  `ifdef hypervisor  
    Bit#(addr)          hgatp;
    Bit#(addr)          vssatp;
    Bit#(TLog#(level))  levels_G;
    Bit#(TLog#(level))  levels_VS;
    Bit#(addr)          gva;
    Bit#(paddr)         gpa;
    TLB_permissions     gpa_perm;
    Bit#(paddr)         hpa;
    TLB_permissions     hpa_perm;
  `endif
  } PTW_response_splitTLB# (numeric type addr, numeric type level, numeric type ppnsize, numeric type asidwidth, numeric type paddr) deriving(Bits, Eq, FShow);
  
  typedef struct{
    Bit#(addr)            address;
    Bit#(3)               size;
    Bit#(2)               access;
    Bool                  ptwalk_trap;
    Bool                  ptwalk_req;
    Bit#(`causesize)      cause;
  } PTwalk_mem_request# (numeric type addr) deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(level_size)  levels ;
    Bit#(ppnsize)     ppn;
    Bit#(2)           widenbits;
  } VM_info #(numeric type level_size, numeric type ppnsize)deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(addr)          addr; //GVA or GPA
    Bit#(ppnsize)       ppn;
    Bit#(TLog#(level))  levels;
    Bool                n;
  } Gen_add#(numeric type addr, numeric type ppnsize, numeric type level) deriving(Bits, Eq, FShow);

  typedef struct{
    Bool              trap;
    Bit#(`causesize)  cause;
  } Trap deriving(Bits, Eq, FShow);
// -------------------------- TLB Structs ----------------------------------------------------//
  typedef struct{
    Bit#(tag_size)        tag;
    Bit#(asidwidth)       asid;
    Bit#(ppnsize)         ppn;	
    TLB_permissions       permissions;
  } TLB_entry# (numeric type tag_size, numeric type ppnsize, numeric type asidwidth) deriving(Bits, Eq, FShow);

`ifdef hypervisor
  typedef struct{
    Bit#(tag_size)                          tag;//gva
    Bit#(ppnsize)                           ppn;
    Bit#(paddr)                             gpa;
    TLB_permissions                         gpa_permissions;
    Bit#(paddr)                             hpa;
    TLB_permissions                         hpa_permissions;
    Bit#(vmidwidth)                         vmid; // for v=0 vmid is asid for v=1 its hgatp.vmid 
    Bit#(asidwidth)                         asid; // for v=0 this will be ssatp.asid for v=1 its vssatp.asid
    Bit#(1)                                 v;
} TLB_entryH# (numeric type tag_size, numeric type ppnsize, numeric type asidwidth, numeric type vmidwidth, numeric type paddr) deriving(Bits, FShow, Eq);
`endif

  typedef struct {
  	Bool v;					//valid
  	Bool r;					//allow reads
  	Bool w;					//allow writes
  	Bool x;					//allow execute(instruction read)
  	Bool u;					//allow supervisor
  	Bool g;					//global page
  	Bool a;					//accessed already
  	Bool d;					//dirty
  } TLB_permissions deriving(Eq, FShow);

  instance Bits#(TLB_permissions,8);
    /*doc:func: */
    function Bit#(8) pack (TLB_permissions p);
      return {pack(p.d), pack(p.a), pack(p.g), pack(p.u), 
              pack(p.x), pack(p.w), pack(p.r), pack(p.v)};
    endfunction
    /*doc:func: */
    function TLB_permissions unpack (Bit#(8) perms);
		  return TLB_permissions { v : unpack(perms[0]),
			  											 r : unpack(perms[1]),
				  										 w : unpack(perms[2]),
					  									 x : unpack(perms[3]),
						  								 u : unpack(perms[4]),
							  							 g : unpack(perms[5]),
								  						 a : unpack(perms[6]),
									  					 d : unpack(perms[7])};
     endfunction
  endinstance

  function TLB_permissions bits_to_permission(Bit#(8) perms);
		return TLB_permissions { v : unpack(perms[0]),
														 r : unpack(perms[1]),
														 w : unpack(perms[2]),
														 x : unpack(perms[3]),
														 u : unpack(perms[4]),
														 g : unpack(perms[5]),
														 a : unpack(perms[6]),
														 d : unpack(perms[7])};
	endfunction
// -------------------------------------------------------------------------------------------//

endpackage

