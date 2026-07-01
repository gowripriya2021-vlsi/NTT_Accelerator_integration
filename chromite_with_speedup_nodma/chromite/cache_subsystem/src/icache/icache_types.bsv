/*
see LICENSE.incore
see LICENSE.iitm

Author: Neel Gala
Email id: neelgala@gmail.com
Details:

--------------------------------------------------------------------------------------------------
*/
package icache_types;
`ifdef supervisor
`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import mmu_types :: * ;
`endif
// ---------------------- Data Cache types ---------------------------------------------//
  typedef struct{
    Bit#(addr)    address;
    Bool          fence;
    Bit#(esize)   epochs;
    Bit#(2)       priv;
  } ICache_core_request#( numeric type addr,
                          numeric type esize) deriving (Bits, Eq, FShow);
  typedef struct{
    Bit#(addr)    address;
    Bit#(8)       burst_len;
    Bit#(3)       burst_size;
    Bool          io;
  } ICache_mem_readreq#( numeric type addr) deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(data)    data;
    Bool          last;
    Bool          err;
  } ICache_mem_readresp#(numeric type data) deriving(Bits, Eq, FShow);


  // ---------------------- Types for IMem and Core interaction ------------------------------- //
  typedef struct{
    Bit#(addr)    address;
    Bit#(esize)   epochs;
    Bool          fence;
    Bit#(2)       priv;
    Bit#(1)       mxr;
    Bit#(1)       sum;
    
  `ifdef supervisor
    Bit#(addr)    satp;
    SfenceReq#(addr, `asidwidth)     sfence_req;
  `ifdef hypervisor
    Bit#(1)       v; 
    Bit#(addr)    hgatp;
    Bit#(addr)    vssatp;
  `endif  
  `endif
  } IMem_core_request#(numeric type addr,
                  numeric type esize ) deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(data)        line;
    Bool              trap;
    Bit#(`causesize)  cause;
    Bit#(esize)       epochs;
  `ifdef hypervisor
    Bit#(paddr)       gpa;
  `endif
  } IMem_core_response#( numeric type data, numeric type esize `ifdef hypervisor ,numeric type paddr `endif ) deriving (Bits, Eq);

  instance FShow#(IMem_core_response#(data, esize `ifdef hypervisor ,paddr `endif ));
    function fshow(IMem_core_response#(data, esize `ifdef hypervisor ,paddr `endif ) val);
      Fmt result = $format("IMem_core_response: trap:%b, cause:%d epochs:%b",val.trap, val.cause,
      val.epochs);
      return result;
    endfunction:fshow
  endinstance
  // -------------------------------------------------------------------------------------------//

// --------------------------- Common Structs ---------------------------------------------------//
  typedef enum {Hit=1, Miss=0, None=2} RespState deriving(Eq,Bits,FShow);
// -------------------------------------------------------------------------------------------//
`ifdef icache_ecc
  typedef struct{
    Bit#(a) address;
    Bit#(w) way;
  } ECC_icache_tag#(numeric type a, numeric type w) deriving(Bits, FShow, Eq);

  typedef struct{
    Bit#(a) address;
    Bit#(b) banks;
    Bit#(w) way;
  } ECC_icache_data#(numeric type a, numeric type w, numeric type b) deriving(Bits, FShow, Eq);


  typedef struct{
    Bit#(TLog#(`isets)) index; 
    Bit#(TLog#(`iways)) way;
    Bit#(TLog#(`iblocks)) banks;
    Bit#(TMul#(`iwords,8)) data;
    Bool read_write; // False: read True: write
    Bool tag_data; // False: tag True: daa
  } IRamAccess deriving (Bits, Eq, FShow);
`endif
endpackage
