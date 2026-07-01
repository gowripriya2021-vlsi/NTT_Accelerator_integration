// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Friday 23 July 2021 11:58:53 AM

Overall Architecture
--------------------

This particular version of the cache uses 1read-1write port versions of the BRAMs. This variant also
includes a word-wide storebuffer to hold all the store requests and also a store-line-buffer which
holds the lines to which stores are to be performed. 
The access to the RAMs require two cycles: one cycle for the actual read of the RAM, and 
another cycle for tag comparison, hit determination and way selection.

Unlike the other variants, this variant does not have a fill-buffer per se except for a single
line-sized buffer which is used to temporariliy store the arriving bytes of missed line.
The variant also includes a separate io-buffer to peform io load/store/atomic operations.

To prevent aliasing issues, the size of each way should not cross 4kiB.
The write-policies followed are write-back and write-allocate. 

The load to use latency of the data-cache is 1 clock cycle.

High-level features:

  - The caches follow a write-back policy. This reduces the traffic to the next-level caches.
  - These are blocking caches. If a miss is encountered, the caches can latch only one more request 
    from the core which will get served only after the previous miss has been served.
  - On a cache-line miss, the caches expect the lower memory/bus to respond with the critical word first.
  - The caches can be disabled at runtime by clearing the corresponding bits in custom control csr 
  - To ensure pipeline-like performance and high-throughput from the above choices, the caches also 
    include a store-line-buffer. The store-line-buffer depth can be configured at compile time. 
    The store-line-buffer is used to hold cache lines from the rams which received a store-hit 
    temporarily.
  - When the store-line-buffer is full or if the cache is idle, the store-line-buffer will release 
    some of the lines into the rams. The opportunistic-release algorithm (discussed later) ensures 
    that store-line-buffer does not reach its capacity often.
  - A release also occurs on a miss, from the single fill-buffer entry
  - It is only during the releases operations (because of a store or fill) that a line from a set 
    gets allotted or evicted.
  - Round-robin, PLRU and Random replacement policies are supported (which need to be defined at 
    compile time). The policy only comes into picture during a release of the fillbuffer.
  - The valid and dirty bits are stored as an array of registers. This enables a single-cycle 
    flush operation for a non-dirty cache. Storing them as register also enables easy control 
    flow-logic during allocation and release phases.
  - The cache also employs a store-buffer. This buffer holds the meta-data of the store/atomic 
    operation to be performed by the core during the execute/memory stage of the core-pipeline. 
    The commit stage of the core instructs the cache to perform the respective store in 
    the store-line-buffer, or simply discard the store entry in case a intermediate trap is observed.
  - When supervisor is enabled, the physical tags for comparison are received from the respective 
    TLBs. The size of the tags depends on the physical address size being employed by the platform. 
    RISC-V ISA can support a maximum of 56-bit physical address for sv39.

Working Principle
-----------------

A request from the core or the ptw is received via the receive_core_req interface and enqueued into
the ff_core_request fifo. The lookup in the rams is also initiated in the same cycle this is
interface is fired in.

In the subsequent cycle, the tags from the rams are compared against the physical address of the
request. On a load hit in the rams, the requried bytes from the selected data line are extracted and sent
back as response to the core or ptw. In the same cycle we also look up for matching lines in the
store-line-buffer and extract relevant bytes from the same. Note, a line can match only in either
the rams or the store-line-buffer and never in both.

On store hit in the rams, the line is moved from the rams to the store-line-buffer as is. The
respective line in the rams is then invalidated and ready to be filled. This is done to ensure that
all store operations from the core are performed on the lines in the store-buffer-line itself,
thereby avoiding the requirement for byte-enabled rams (which can be costly at times).

On a load miss, when a the requested bytes arrive from the lower memory/bus they are immediately
passed on to the core to avoid further stalls. On a store miss, however the core is responded only
when all the bytes of the line have arrived. Also for a store operation, the filled line is moved in
to the store-line-buffer while for a load operation the fill line is moved into the rams. 

When the store-line-buffer is full or when the cache is idle (not processing any requests), the
store-line-buffer will take the oppurtunity to release its ready lines (lines to which there are no
pending stores in the pipeline) to the rams. 

Both types of releases, store-line release and a fill-line release, can cause an eviction of a dirty
line in the rams.

Fence operation
^^^^^^^^^^^^^^^

A cache-flush operation is initiated when the core presents a fence instruction. A fence operation 
can only start if following conditions are met:

1. the entire store-buffer is empty (i.e. all lines are updated in the SRAM and there are no pending 
   stores to be committed).
2. there are not pending evictions to be peformed
3. there is no pending miss that is being handled.
4. there is no io operations that are pending in the io-buffer to be committed.

The fence operation is a single cycle operation if the global-dirty bit 
is clear, where all the lines are invalidated and the dirty bits of each line are cleared as well. 
If the global-dirty bit is set, the fence operation in the cache traverses through each set and 
identifies which lines need to the written back to the fabric. Traversing a set, requires 
traversing each of the way and checking if an eviction is required. A set is ignored 
if there are no valid dirty lines in the set. At the end of each set traversal, the valid and 
dirty bits of the entire set are cleared. The fence operation in the D-Cache is only over when the 
last set has been completely traversed. Until this point, not new requests are entertained from the 
core-side.

*/
package dcache1r1w;
`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;
  import GetPut       :: * ;
  import Assert       :: * ;
  import OInt         :: * ;
  import DReg         :: * ;
  import BUtils       :: * ;
  import ConfigReg    :: * ;
  
  `include "Logger.bsv"
  `include "dcache.defines"
  
  import dcache_types :: * ;
  import dcache_lib :: * ;
  import replacement_dcache :: * ;
  import io_func :: * ;
`ifdef supervisor
  import mmu_types:: * ;
`endif
`ifdef dcache_ecc
  import ecc_hamming :: * ;
`endif
`ifdef pmp
  import pmp_func :: *;
`endif

  /*doc:struct:
  This structure holds the information required for handling a miss. Since in this version of the
  cache, we send the response from the fill itself, this struct needs to hold a lot of fields from
  the original virtual request itself.
  */
  typedef struct{
  `ifdef supervisor
    Bool req_is_ptw;
  `endif
  `ifdef atomic
    Bit#(5) atomic_op;
    Bit#(TMul#(`dwords,8)) wdata;
  `endif
    Bit#(`vaddr) vaddr;
    Bit#(TLog#(`dsbsize)) sbid;
    Bit#(2) access;
    Bit#(`paddr) phy_addr;
    Bit#(3) access_size;
    Bit#(`desize) epochs;
  } MissMeta deriving(Bits, FShow, Eq);

  
  interface Ifc_dcache;
    /*doc:subifc: This interface receives the virtual request from the core side. This interface
    * will initiate the look-up on the brams and enq the request into a fifo for being processed in
    * the subsequent cycle(s)*/
    interface Put#(DCache_core_request#(`vaddr,TMul#(`dwords,8),`desize)) receive_core_req;

    /*doc:subifc: This sub interface will send the response back to the core. This is usually driven
     * a simple bypass FIFO*/
    interface Get#(DMem_core_response#(TMul#(`dwords,8),`desize `ifdef hypervisor ,`paddr `endif ))         send_core_cache_resp;

    /*doc:subifc: This sub interface will be used to send the responses back to the core for all IO
     * requests that were received*/
    method Maybe#(DMem_core_response#(TMul#(`dwords,8),`desize `ifdef hypervisor ,`paddr `endif ))          send_core_io_resp;

    /*doc:subifc: This sub interface will be used to send line read requests to the lower level on
     *a miss. This is usually driven a sized FIFO*/
    interface Get#(DCache_mem_readreq#(`paddr)) send_mem_rd_req;

    /*doc:subifc: This sub interface will receive the data from the lower levels in chunks*/
    interface Put#(DCache_mem_readresp#(`dbuswidth)) receive_mem_rd_resp;

    /*doc:subifc: This sub interface is used to send out memory write requests during evictions*/
    method DCache_mem_writereq#(`paddr, TMul#(`dblocks, TMul#(`dwords, 8))) send_mem_wr_req;

    /*doc:method: The following action method is used to indicate that the write-request has been
     * picked/acknowledge and thus the fifo can be popped*/
    method Action deq_mem_wr_req;

    /*doc:subifc: This sub interface captures the write-response for each eviction*/
    interface Put#(DCache_mem_writeresp) receive_mem_wr_resp;

    /*doc:subifc: this sub interface is used to send out the io memory requests to the bus*/
    interface Get#(DCache_io_req#(`paddr, `dbuswidth)) send_mem_io_req;

    /*doc:subifc: this sub interface is used to receive the io memory responses*/
    interface Put#(DCache_io_response#(`dbuswidth)) receive_mem_io_resp;

    /*doc:method: This method is used to capture the current privilege mode under which operations
     * are being performed*/
    // method Action ma_curr_priv (Bit#(2) c);

    /*doc:method: this method captures whether the cache is enabled or not. Handling switching
    * between enable/disable needs to be done properly in the SW. There is not HW role here other
    * than bypassing the RAMS.*/
    method Action ma_cache_enable(Bool c);

    /*doc:method: this method indicates is the storebuffer is empty*/
    method Bool mv_storebuffer_empty;

    /*doc:method: this method indicates if the cache is available for accepting new requests from
     * the core. This method should be used by requesting modules to know when to latch a new
    * request*/
    method Bool mv_cache_available;

    /*doc:method: This method indicates that a particular store buffer entry is ready to commit into
     * the line*/
    method Action ma_commit_store(Tuple2#(Bit#(`desize),Bit#(1)) c);

    /*doc:method: This method indicates that the top/head of the io buffer can be committed*/
    method Action ma_commit_io(Bit#(`desize) currepoch);


  `ifdef supervisor
    /*doc:subifc: sub interface to send responses to the ptw module instead of the core*/
    interface Get#(DMem_core_response#(TMul#(`dwords,8),`desize `ifdef hypervisor ,`paddr `endif )) get_ptw_resp;

    /*doc:subifc: sub interface to received the translation result from the tlb*/
    interface Put#(DTLB_core_response#(`paddr)) put_pa_from_tlb;

    /*doc:subifc: inteface to the ptw module indicating that the current request needs to be parked
     * until the ptwalk is done*/
    interface Get#(DCache_core_request#(`vaddr, TMul#(`dwords, 8), `desize)) get_hold_req;
  `endif

  `ifdef perfmonitors
    method Bit#(13) mv_perf_counters;
  `endif

  `ifdef dcache_ecc
    method Maybe#(ECC_dcache_data#(`paddr, `dways, `dblocks)) mv_ded_data;
    method Maybe#(ECC_dcache_data#(`paddr, `dways, `dblocks)) mv_sed_data;
    method Maybe#(ECC_dcache_tag#(`paddr, `dways)) mv_ded_tag;
    method Maybe#(ECC_dcache_tag#(`paddr, `dways)) mv_sed_tag;
    method Action ma_ram_request(DRamAccess access);
    method Bit#(`respwidth) mv_ram_response;
  `endif
  endinterface : Ifc_dcache

  /*doc:func: This function is used to re-align and extract the correct set of bytes as per the
   * request received. The input to this function is the address (to get the byte offsets), the size
   * of the request (byte, hword, word, dword, etc) and the actual data from the line. The function
   * will use the byte offset to extract the bytes and sign/zero Extend the value to fit the
   * response width.
   */
  function Bit#(`respwidth) fn_realign_n_update(Bit#(`paddr) addr, Bit#(3) size, 
                                                                   Bit#(`respwidth) block);
  
    Bit#(3) zeros = 0;
    Bit#(TAdd#( `wordbits ,3)) shiftamt = {truncate(addr), zeros};
    let word = block >> shiftamt;
    Bit#(1) lv_sign =case(size[1:0])
        'b00: word[7];
        'b01: word[15];
        default: word[31];
      endcase;
    // manipulate the sign based on the request of the core
    lv_sign = lv_sign & ~size[2];
    // generate a mask based on the request of the core.
    Bit#(`respwidth) mask = case(size[1:0])
      'b00: 'hFF;
      'b01: 'hFFFF;
      'b10: 'hFFFFFFFF;
      default: '1;
    endcase;
    Bit#(`respwidth) signmask = ~mask & duplicate(lv_sign);
    let lv_response = (word & mask) | signmask;
    return lv_response;
  endfunction: fn_realign_n_update
`ifdef atomic
  /*doc:func: This function carries out the atomic operations based on the RISC-V ISA spec. This
  * function is required in this module for the io atomic operations*/
  function Bit#(TMul#(`dwords,8)) fn_atomic_io_op (Bit#(5) op,  Bit#(TMul#(`dwords,8)) rs2,  Bit#(TMul#(`dwords,8)) loaded);
    // op1 holds the read value
    Bit#(TMul#(`dwords,8)) op1 = loaded;

    // op2 holds the write value
    Bit#(TMul#(`dwords,8)) op2 = rs2;

  `ifdef RV64
    // sign extend the operands if they are 32-bit ops
    if(op[4]==0)begin
      op1=signExtend(loaded[31:0]);
      op2= signExtend(rs2[31:0]);
    end
  `endif
    // create signed integers from the inputs for signed comparison ops.
    Int#(TMul#(`dwords,8)) s_op1 = unpack(op1);
    Int#(TMul#(`dwords,8)) s_op2 = unpack(op2);

    case (op[3:0])
        'b0011:return op2;
        'b0000:return (op1+op2);
        'b0010:return (op1^op2);
        'b0110:return (op1&op2);
        'b0100:return (op1|op2);
        'b1100:return min(op1,op2);
        'b1110:return max(op1,op2);
        'b1000:return pack(min(s_op1,s_op2));
        'b1010:return pack(max(s_op1,s_op2));
        default:return op1;
      endcase
  endfunction
`endif


  (*synthesize*)
  (*conflict_free="rl_ram_check, ma_commit_store"*)
  (*descending_urgency="rl_io_response, ma_commit_io"*)
  (*conflict_free="ma_commit_store, rl_fill_from_memory"*)
  (*conflict_free="rl_ram_check, rl_store_release"*)
  (*descending_urgency="rl_io_response, rl_ram_check"*)

  // following have a conflict on rg_fence_stall
  (*conflict_free="rl_fence_operation, receive_core_req_put"*)

  // when store release is firing stall miss handling
  (*preempts="rl_store_release, rl_fill_from_memory"*)
  (*preempts="rl_fill_release, rl_store_release"*)
  module mkdcache#( parameter Bit#(32) id
    `ifdef pmp ,
        Vector#(`pmpentries, Bit#(8)) pmp_cfg, 
        Vector#(`pmpentries, Bit#(`paddr)) pmp_addr `endif
    )(Ifc_dcache);

    String dcache = "";
    let v_sets=valueOf(`dsets);
    let v_setbits=valueOf(`setbits);
    let v_wordbits=valueOf(`wordbits);
    let v_blockbits=valueOf(`blockbits);
    let v_linewidth=valueOf(`linewidth);
    let v_paddr=valueOf(`paddr);
    let v_ways=valueOf(`dways);
    let v_wordsize=valueOf(`dwords);
    let v_blocksize=valueOf(`dblocks);
    let v_respwidth=valueOf(`respwidth);
    let v_fbsize = valueOf(`dfbsize);
    let v_tagbits = valueOf(`tagbits);
    let v_ecc_size = valueOf(`deccsize);

    let m_data <- mkdcache_data(id);
    let m_tag <- mkdcache_tag(id);
    let m_storebuffer <- mkstorebuffer(id);
    let m_iobuffer <- mkiobuffer(id);
    
    // ----------------------- FIFOs to interact with interface of the design -------------------//
    /*doc:fifo: This fifo stores the request from the core.*/
    FIFOF#(DCache_core_request#(`vaddr, `respwidth, `desize)) ff_core_request <- mkUGSizedFIFOF(2);

    /*doc:fifo: This fifo stores the response that needs to be sent back to the core.*/
    FIFOF#(DMem_core_response#(`respwidth,`desize `ifdef hypervisor ,`paddr `endif ))ff_core_response <- mkSizedBypassFIFOF(2);
    /*doc:reg: */
    Reg#(Maybe#(DMem_core_response#(`respwidth, `desize `ifdef hypervisor ,`paddr `endif ))) rg_core_io_response <- mkDReg(tagged Invalid);
  `ifdef supervisor
    /*doc:fifo: This fifo stores the response that needs to be sent back to the ptw.*/
    FIFOF#(DMem_core_response#(`respwidth,`desize `ifdef hypervisor ,`paddr `endif ))ff_ptw_response <- mkBypassFIFOF();
  `endif
    /*doc:fifo: this fifo stores the read request that needs to be sent to the next memory level.*/
    FIFOF#(DCache_mem_readreq#(`paddr)) ff_mem_rd_request <- mkSizedFIFOF(2);
    /*doc:fifo: This fifo stores the response from the next level memory.*/
    FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_mem_rd_resp  <- mkBypassFIFOF();
    /*doc:fifo: this fifo stores the eviction request to be written back*/
    FIFOF#(DCache_mem_writereq#(`paddr, `linewidth)) ff_mem_wr_request <- mkFIFOF1;
    /*doc:fifo: this fifo stores the write response from an eviction or a io write req*/
    FIFOF#(DCache_mem_writeresp) ff_mem_wr_resp  <- mkBypassFIFOF();
    /*doc:fifo: this fifo holds the request from core when there has been a tlbmiss */
    FIFOF#(DCache_core_request#(`vaddr, `respwidth, `desize)) ff_hold_request <- mkBypassFIFOF();
    /*doc:fifo: fifo to hold the IO requests going directly to the bus*/
    FIFOF#(DCache_io_req#(`paddr, `dbuswidth)) ff_mem_io_request <- mkFIFOF1();
    /*doc:fifo: fifo holding the IO responses coming directly from the bus*/
    FIFOF#(DCache_io_response#(`dbuswidth)) ff_mem_io_resp <- mkFIFOF1();
    

  `ifdef supervisor
    /*doc:fifo: this fifo receives the physical address from the TLB */
    FIFOF#(DTLB_core_response#(`paddr)) ff_from_tlb <- mkBypassFIFOF();
  `endif
    // -------------------- Register declarations ----------------------------------------------//

    /*doc:reg: register when True indicates a fence is in progress and thus will prevent taking any
     new requests from the core*/
    Reg#(Bool) rg_fence_stall <- mkReg(False);
    
    /*doc:reg: When tru indicates that a miss is being catered to*/
    ConfigReg#(Bool) rg_miss_handling <- mkConfigReg(False);

    /*doc:reg: this register indicates that the io buffer has initiated an IO transaction and is
    * waiting for response*/
    Reg#(Bool) rg_io_busy <- mkReg(False);

  `ifdef atomic
    /*doc:reg: register holding the reservation address*/
    Reg#(Maybe#(Bit#(`vaddr))) rg_reservation_address <- mkReg(tagged Invalid);
  `endif
    // ----------------------- Storage elements -------------------------------------------//

    /*doc:reg: This is an array of the valid bits. Each entry corresponds to a way and contains
    'set' number of bits in each entry*/
    Vector#(`dways, Reg#(Bit#(`dsets))) v_reg_valid <- replicateM(mkReg(0));

    /*doc:reg: This is an array of the dirty bits. Each entry corresponds to a way and contains
    'set' number of bits in each entry*/
    Vector#(`dways, Reg#(Bit#(`dsets))) v_reg_dirty <- replicateM(mkReg(0));

    /*doc:submod: Instantiate the replacement module*/
    Ifc_replace#(`dsets,`dways) replacement <- mkreplace(`drepl);

    /*doc:reg: register containing the line to be evicted*/
    Reg#(Bit#(`linewidth)) rg_evicted_line <- mkRegU();

    /*doc:reg: holds the address of the line to be evicted.*/
    Reg#(Bit#(`paddr)) rg_evict_addr <- mkReg(0);
  
    /*doc:reg: boolean flag indicating that an eviction of a line is required after the stall is complete*/
    Reg#(Bool) rg_eviction_required <- mkReg(False);

    /*doc:reg: to keep track of the block number within a line that the lower memory is responding
     * with*/
    Reg#(Bit#(`dblocks)) rg_block_count <- mkReg(0);

    /*doc:reg: register indicates that there is atleast one dirty line in the RAMS. This register is
    * useful during fence, where the fence can complete in a single cycle if this register is False*/
    Reg#(Bool) rg_global_dirty <- mkReg(False);

    /*doc:reg: this register indicates that the IO op is part of an atomic op and the read phase is
    * over when this register is set.*/
    Reg#(Bool) rg_io_atomic_done <- mkReg(False);

    /*doc:reg: */
    Reg#(Bit#(`respwidth)) rg_atomic_rd_data <- mkReg(0);

    //---------------- Fill handling registers --------------------------------------------//

    /*doc:reg: register to hold the line that is being filled by the lower memory*/
    Vector#( `dblocks, Reg#(Bit#(`respwidth)) ) v_fill_line <- replicateM(mkRegU()) ;

    /*doc:reg: when true this register indicates if the fill buffer is ready to be released into the
    * RAMs*/
    ConfigReg#(Bool) rg_fill_release <- mkConfigReg(False);

    /*doc:reg: register indicating the set the fill line should write into*/
    ConfigReg#(Bit#(TMax#(1, `setbits))) rg_fill_set <- mkConfigReg(0);

    /*doc:reg: register pointing to the way of the set that the fill should write into*/
    ConfigReg#(Bit#(TLog#(`dways))) rg_fill_way <- mkConfigReg(0);

    /*doc:reg: register holding the tag value to be written in to the selected fill entry*/
    ConfigReg#(Bit#(`tagbits)) rg_fill_tag <- mkConfigReg(0);

    /*doc:reg: records the occurance of bus error so that that particular cache line can be invalidated*/
    ConfigReg#(Bool) rg_fill_err <- mkConfigReg(False);

    /*doc:reg: when true this line indicates that the fill release will require eviction*/
    ConfigReg#(Bool) rg_fill_eviction <- mkConfigReg(False);

    /*doc:reg: register indicates that the response from the lower memory is the first word of the
    * line and thus should be responded to the core/ptw module on arrival*/
    Reg#(Bool) rg_first <- mkReg(True);

    // ----------------------------------------------------------------------------------//

    /*doc:reg: this register holds the information that will be required to fill data coming from the
    * bus to the cache*/
    Reg#(MissMeta) rg_miss_meta <- mkReg(unpack(0));

    /*doc:reg: This register indicates that the bram inputs are being re-driven by those provided
    from the core in the most recent request. This happens because as the release from the
    fillbuffer happens it is possible that a dirty ways needs to be read out. This will change the
    output of the brams as compared to what the core requested. Thus the core request needs to be
    replayed on these again */
    Reg#(Bool) rg_performing_replay[2] <- mkCRegA(2,False);

    /*doc:reg: this register holds the index of the most recent request performed by the core*/
    ConfigReg#(Bit#(TMax#(1, `setbits))) rg_recent_req <- mkConfigRegA(0);

    /*doc:reg: for pointing to the way that needs to be read during fence operations*/
    Reg#(Bit#(`dways)) rg_fence_way <- mkRegA(1);

    /*doc:reg: for pointting to the set that needs to be read during fence operations*/
    Reg#(Bit#(TMax#(1,`setbits))) rg_fence_set <- mkRegA(0);

    /*doc:reg: when true this line indicates that the fill release will require eviction*/
    Reg#(Bool) rg_store_eviction <- mkDReg(False);

    // -------------------- Wire declarations ----------------------------------------------//

    /*doc:wire: wire which drives the index input port of the brams for read operations*/
    Wire#(Bit#(TMax#(1,`setbits))) wr_read_set_index <- mkWire();

    /*doc:wire: boolean wire indicating if the cache is enabled. This is controlled through a csr*/
    Wire#(Bool) wr_cache_enable<-mkDWire(True);
    /*doc:wire: wire holds the current privilege mode of the core*/
    // Wire#(Bit#(2)) wr_priv <- mkWire();
  `ifdef perfmonitors
    /*doc:wire: wire to pulse on every read access*/
    Wire#(Bit#(1)) wr_total_read_access <- mkDWire(0);
    /*doc:wire: wire to pulse on every write access*/
    Wire#(Bit#(1)) wr_total_write_access <- mkDWire(0);
    /*doc:wire: wire to pulse on every atomic access*/
    Wire#(Bit#(1)) wr_total_atomic_access <- mkDWire(0);
    /*doc:wire: wire to pulse on every io read access*/
    Wire#(Bit#(1)) wr_total_io_reads <- mkDWire(0);
    /*doc:wire: wire to pulse on every io write access*/
    Wire#(Bit#(1)) wr_total_io_writes <- mkDWire(0);
    /*doc:wire: wire to pulse on every read miss within the cache*/
    Wire#(Bit#(1)) wr_total_read_miss <- mkDWire(0);
    /*doc:wire: wire to pulse on every write miss within the cache*/
    Wire#(Bit#(1)) wr_total_write_miss <- mkDWire(0);
    /*doc:wire: wire to pulse on every atomic miss within the cache*/
    Wire#(Bit#(1)) wr_total_atomic_miss <- mkDWire(0);
    /*doc:wire: wire to pulse on every eviction from the cache*/
    Wire#(Bit#(1)) wr_total_evictions <- mkDWire(0);
  `endif

    // --------------------------- global variables ------------------------------------- //
    // this variable is set when both the store buffer and the store-line buffer are both empty.
    // The fence can only start when the store buffer is empty
    Bool sb_empty = m_storebuffer.mv_line_empty && m_storebuffer.mv_sb_empty;

    // this variable is set when either the store buffer or the store-line buffer are full. When
    // this variable is true, no more new requests can be taken.
    Bool sb_full = m_storebuffer.mv_line_full || m_storebuffer.mv_sb_full;

    // this variable is set when the store-buffer is performing an atomic operations. When this
    // variable is set, no more requests can be processed.
    Bool sb_busy = m_storebuffer.mv_sb_busy;

    // this variable is set when the io buffer is empty. The fence can only occur when all io
    // operations are complete.
    Bool io_empty = m_iobuffer.mv_io_empty;

    // this variable is set whent he io buffer is full. No more requests can be taken when the
    // io_buffer is full.
    Bool io_full  = m_iobuffer.mv_io_full;

    /*doc:rule: rule to simply acknowledge all memory write responses and pop them from the fifo*/
    rule rl_deq_mem_wr_resp;
      ff_mem_wr_resp.deq;
    endrule:rl_deq_mem_wr_resp

    /*doc:rule: This rule drives the read input ports of the rams. This rule will only fire when the
    * wr_read_set_index wire is written to. A read can coocur because of any of the following
    * actions: a new request from the core/ptwalk, a fence operation wants to read a dirty line, a
    * fill-eviction wants to read a dirty line, a store-eviction wants to read a dirty line.*/
    rule rl_drive_ram_read_port;
      m_tag.ma_read_p1(wr_read_set_index);
      m_data.ma_read_p1(wr_read_set_index,'1);
    endrule:rl_drive_ram_read_port

    /*doc:rule: This rule performs a fence operation on the cache. It will evict all dirty lines in
     * the rams to the lower level memory. The rule can only fire when : the store buffer is empty,
     * io buffer is empty, no pending core requests exist, no miss is being handled and any
     * previous eviction has completed successfully.
     *
     * The rule maintains its own set and way counter which is used to access and read dirty lines
     * from the ram. The set is a basic counter, while the way-counter is maintained as a one-hot
     * counter.
     *
     * If the global_dirty variable is not set then the fence operation completes in a single cycle
     * by setting all the valid and dirty bits of all ways and sets to 0. Else, once all the dirty
     * lines have been evicted, the valid and dirty bits are cleared.
     *
     * Once the fence operation is over it will respond to back to core indicating the completion.
    */
    rule rl_fence_operation(rg_fence_stall && ff_core_request.first.fence && sb_empty && io_empty
            && ff_core_request.notEmpty && !rg_performing_replay[0] 
            && !rg_miss_handling && !rg_eviction_required);
      `logLevel( dcache, 0, $format("[%2d]DCACHE: Fence processing set:%d way:%b",id,rg_fence_set, rg_fence_way))
      `logLevel( dcache, 0, $format("[%2d]DCACHE: Fence flags: v:%d d:%d",id,
                       v_reg_valid[fromOInt(unpack(rg_fence_way))][rg_fence_set],
                       v_reg_dirty[fromOInt(unpack(rg_fence_way))][rg_fence_set]))

      let lv_fence_set = rg_fence_set;

      // read the data line and tag entries from the rams.
      let lv_line = m_data.mv_lineselect_p1(rg_fence_way);
      Bit#(`tagbits) lv_tag <- m_tag.mv_select_p1(rg_fence_way);

      // address of the line that may be evicted
      Bit#(`paddr) lv_address=?;
      lv_address = (v_setbits != 0)? {lv_tag,rg_fence_set, 'd0} : {lv_tag, 'd0};

      // check if the current line is dirty and requires eviction
      Bit#(`dways) lv_set_valid=?;
      Bit#(`dways) lv_set_dirty=?;
      for (Integer i = 0; i<`dways ; i = i + 1) begin
        lv_set_valid[i] = v_reg_valid[i][rg_fence_set];
        lv_set_dirty[i] = v_reg_dirty[i][rg_fence_set];
      end
      if (|(lv_set_dirty & lv_set_valid & rg_fence_way) == 1) begin
        rg_eviction_required <= True;
        `logLevel( dcache, 0, $format("[%2d]DCACHE: Fence evicting addr:%h data:%h",id,
          lv_address, lv_line))
      end
      // set is incremented when the msb bit of the way-counter becomes one indicating all ways of
      // the particular set have been processed.
      if (v_setbits != 0)
        lv_fence_set = rg_fence_set + zeroExtend(rg_fence_way[`dways-1]);

      wr_read_set_index <= lv_fence_set;
      rg_evicted_line <= lv_line.line;
      rg_evict_addr <= lv_address;

      // when rg_global_dirty is False or when the last way of the last set has been processed end
      // the operation.
      if( !rg_global_dirty || (rg_fence_set == fromInteger(`dsets-1) && rg_fence_way[`dways-1] == 1)) begin
        for (Integer i = 0; i<`dways; i = i + 1) begin
          v_reg_valid[i] <= 0;
          v_reg_dirty[i] <= 0;
        end
        rg_fence_stall <= False;
        rg_global_dirty <= False;
        rg_fence_set <= 0;
        rg_fence_way <= 1;
        replacement.reset_repl;
        ff_core_request.deq;
        ff_core_response.enq(DMem_core_response{word:?, trap: False, is_io: False,
                             cause: ?, epochs: ff_core_request.first.epochs,
                             entry_alloc: False, sb_id: ?
                             `ifdef hypervisor ,gpa: ? `endif });
      end
      else begin
        rg_fence_set <= lv_fence_set;
        rg_fence_way <= rotateBitsBy(rg_fence_way,1);
      end
    endrule:rl_fence_operation
    
    /*doc:rule: This rule checks the cache data structures for a hit or a miss on a given
    * core/ptwalk request. This rule will check the rams and the store-line-buffers if they contain
    * the required words.
    * The rule can only fire when there is a valid core request pending from the previous cycle,
    * there is no miss that is pending, store-buffer and store-line-buffer are not full, io-buffer
    * is not full and there is not pending eviction in the fifo.
    *
    * The reason we include no pending eviction in the predicate is to ensure that there is not race
    * between the line being a miss in the cache while its pending eviction. This may cause the
    * read to move ahead of the write and thereby cause a raw hazard on the memory location.
    * 
    * The rule starts by reading the tags and dataline from the rams. The tags are compared to
    * pysical tag (obtained either from the tlbs or from the core request itself). A one-hot hit
    * mask is created as an artifact of this comparison. If atleast one bit is set then a hit in the
    * rams is declared, else its a miss in the rams. The one-hot hit mask is also used to select the
    * line and thereby the word that needs to be sent to the core/ptw as a response.
    * 
    * The rule will also check the store-line-buffer for a possible hit. Note, there cannot be a hit
    * in both the rams and store-line-buffer. There is an assertion to ensure this property. 
    * 
    * on a hit (either in rams or store-line-buffer) the word is sent to the realign function and
    * then forwarded to the core/ptw module. In case of a store-operation being a hit in the rams,
    * we move the hit-line to the store-line-buffer and invalidate the line in the rams.
    * 
    * On a miss however, the rule sends out a line read request to the lower memory and stores the
    * request parameters in the rg_miss_meta register for further handling. On a miss the
    * rg_miss_handling register is set which prevents any further core/ptw requests to be processed
    * until the current miss operation has been handled. 
    *
    * On a hit or miss, if the operation is valid (i.e. no faults raised) and its a store operation
    * we allocate an entry in the store-buffer (not the store-line-buffer).
    * 
    * If the request is an LR or SC operation, first the reservation is checked. in case of an LR,
    * a new reservation is made and the operation id degraded to a simple load operation. In case of
    * SC, we check if the reservation holds. If it does then we treat the operation as a regular
    * atomic op (with the op doing nothin in the compute phase), else its treated as a load op which
    * returns the value of 1 to the core.
    * 
    * If the physical address of the request is in the non-cacheable region, then we allocate an
    * entry in the IO buffer and indicate the same to the core in the response. We then wait for the
    * core to send a commit-io signal which can trigger the actions of the IO operation from the
    * io-buffer.
    *
    * If the tlb responds with a pagefault, then we immediately respond to the core with a fault and
    * do not futher process the request. If the tlb responds with a tlb-miss, then the request is
    * parked into a hold-req fifo which is then sent over to the ptw module. In both cases the
    * request fifo is dequed to allow processing of the next request.
    * 
    * if pmp is enabled, then the pmp checks are performed on the physical address obtained in this
    * rule and appropriate faults/exceptions are raised.
    */

    //rule rl_debug_blocked(ff_core_request.notEmpty && io_full);
    //$display("[DCACHE BLOCKED] io_full=1 vaddr=%08x", ff_core_request.first.address);
    //endrule
    //rule rl_debug_iobuf_state(True);
    //if (io_full)
        //$display("[IOBUF] full! io_empty=%0d rg_io_busy=%0d", pack(io_empty), pack(rg_io_busy));
    //endrule
    rule rl_ram_check(!ff_core_request.first.fence && !rg_miss_handling && !sb_full && !io_full
                      && !sb_busy && !rg_eviction_required && !rg_performing_replay[0]
                      && ff_core_request.notEmpty && !ff_mem_wr_request.notEmpty
                  `ifdef dcache_ecc && !rg_perform_sec && !rg_halt_ram_check `endif );

      let req = ff_core_request.first;
      `logLevel( dcache, 2, $format("[%2d]DCACHE: RAM Processing Req:",id,fshow(req)))

      // select the physical address and check for any faults
    `ifdef supervisor
      let pa_response = ff_from_tlb.first;
      Bit#(`paddr) phyaddr = pa_response.address;
    `ifdef hypervisor 
      let gpa = pa_response.gpa;
    `endif
      Bool lv_access_fault = pa_response.trap ;
      Bool lv_tlbmiss = pa_response.tlbmiss;
      Bit#(`causesize) lv_cause = lv_access_fault? pa_response.cause:
                                  req.access == 0?`Load_access_fault:`Store_access_fault;
      //$display("[DCACHE REQ] vaddr=%08x phyaddr=%08x tlbmiss=%0d access=%0d",
       //        req.address, phyaddr, pack(lv_tlbmiss), req.access);
      `logLevel( dcache, 1, $format("[%2d]DCACHE: Response from PA:",id,fshow(pa_response)))
    `else
      Bit#(TSub#(`vaddr,`paddr)) upper_bits=truncateLSB(req.address);
      Bit#(`paddr) phyaddr = truncate(req.address);
      Bool lv_access_fault = unpack(|upper_bits);
      Bit#(`causesize) lv_cause = req.access == 0?`Load_access_fault:`Store_access_fault;
    `endif
    `ifdef pmp
      Bit#(2) pmp_access = req.access == 0 ? 0 : 1;
      let pmpreq = PMPReq{ address: phyaddr, access_type:pmp_access};
      let {pmp_err, pmp_cause} = fn_pmp_lookup(pmpreq, unpack(req.priv),
                                              pmp_cfg, pmp_addr);
      if (!lv_access_fault && pmp_err)begin
        lv_access_fault = True;
        lv_cause = pmp_cause;
      end
    `endif
      
      Bool skip_op = False;
      Bool sc_pass = False;
    `ifdef atomic
      if (req.access == 2 && req.atomic_op[3:0]=='b0101 `ifdef supervisor && !pa_response.tlbmiss `endif ) begin// LR op
        rg_reservation_address <= tagged Valid (req.address & `reservation_mask);
        req.access = 0;
        `logLevel( dcache, 0, $format("[%2d]DCACHE: LR reservation for : %h",id,req.address))
      end
      else if (req.access == 2 && req.atomic_op[3:0] == 'b0111 `ifdef supervisor && !pa_response.tlbmiss `endif ) begin // SC op
        rg_reservation_address <= tagged Invalid;
        if (rg_reservation_address matches tagged Valid .resaddr &&& 
                                                resaddr  == (req.address & `reservation_mask))begin
          req.access = 2; // change this op to store
          sc_pass = True;
          `logLevel( dcache, 0, $format("[%2d]DCACHE: SC succeeds for : %h ",id,req.address))
        end
        else begin
          req.access = 0; // change this op to load and exit
          skip_op = True;
          `logLevel( dcache, 0, $format("[%2d]DCACHE: SC fails for : %h. ResAddr:%h",id,req.address,
            fromMaybe(?,rg_reservation_address)))
        end
      end
    `endif

      Bit#(`blockbits) lv_blocknum = 0;
      if (v_blockbits !=0 ) lv_blocknum = phyaddr[v_blockbits+v_wordbits-1:v_wordbits];
      Bit#(`wordbits) word_offset = truncate(phyaddr);
      Bit#(TMax#(1, `setbits)) set_index= 0;
      if (v_setbits !=0 ) set_index = phyaddr[v_setbits+v_blockbits+v_wordbits-1:v_blockbits+v_wordbits];
      let lv_io_req = !(phyaddr >= 'h8000_0000 && phyaddr <= 'h8FFF_FFFF) ||  (phyaddr == 'h8000_1000);
      Bit#(`dways) lv_set_valid=?;
      Bit#(`dways) lv_set_dirty=?;
      for (Integer i = 0; i<`dways ; i = i + 1) begin
        lv_set_valid[i] = v_reg_valid[i][set_index];
        lv_set_dirty[i] = v_reg_dirty[i][set_index];
      end
      let lv_tag_resp <- m_tag.mv_tagmatch_p1(phyaddr);
      Bit#(`dways) lv_hitmask = lv_tag_resp.waymask & lv_set_valid;
      let lv_data_resp = m_data.mv_wordselect_p1(lv_blocknum, lv_hitmask);
      let response_word = lv_data_resp.word;
      `logLevel( dcache, 2, $format("[%2d]DCACHE: RAM Hit:%b ",id,lv_hitmask))

      let sb_lookup <- m_storebuffer.mav_core_lookup(phyaddr);
      if (sb_lookup.hit) response_word = sb_lookup.word;
      `logLevel( dcache, 0, $format("[%2d]DCACHE: SB hit:%b",id,sb_lookup.hit))
      Bool hit = unpack(|lv_hitmask) || sb_lookup.hit;
    `ifdef ASSERT
      dynamicAssert(countOnes(lv_hitmask) <= 1,"DCACHE: More than one way is a hit in the cache");
      dynamicAssert((|lv_hitmask & pack(sb_lookup.hit)) == 0, "DCACHE: Hit in SB and RAMS simultaneously");
    `endif
      let lv_response = DMem_core_response{word:response_word, trap: lv_access_fault,
                                          is_io: lv_io_req, cause: lv_cause, epochs: req.epochs,
                                          entry_alloc: (!skip_op && lv_io_req) || req.access != 0, 
                                          sb_id: m_storebuffer.mv_sb_tail
                                          `ifdef hypervisor ,gpa: gpa `endif };
      // capture the sign bit of the response to the core
      lv_response.word = fn_realign_n_update(phyaddr, req.size, lv_response.word);
      lv_response.word = (lv_response.trap || lv_io_req)?truncateLSB(req.address):lv_response.word;
    `ifdef atomic
      if (skip_op)
        lv_response.word = 1;
      else if (sc_pass)
        lv_response.word = 0;
    `endif

      // -- variables for sending memory request
      if (req.access != 0 && !lv_access_fault && !lv_io_req `ifdef supervisor && !pa_response.tlbmiss `endif ) begin
        `logLevel( dcache, 0, $format("[%2d]DCACHE: Allocating Store Buffer",id))
        let lbindex = (sb_lookup.hit)?sb_lookup.lbindex: m_storebuffer.mv_lb_tail;
        m_storebuffer.ma_allocate_store(phyaddr,req.data, req.epochs, truncate(req.size), lbindex);
      `ifdef atomic
        if (hit && req.access == 2 )
          m_storebuffer.ma_perform_atomic(req.atomic_op, lv_response.word, req.data, 
                                                                          m_storebuffer.mv_sb_tail);
      `endif
        if (!sb_lookup.hit && (|lv_hitmask == 1)) begin
          m_storebuffer.ma_allocate_line(phyaddr,lv_data_resp.line);
          v_reg_valid[fromOInt(unpack(lv_hitmask))][set_index] <= 0;
          v_reg_dirty[fromOInt(unpack(lv_hitmask))][set_index] <= 0;
          `logLevel( dcache, 0, $format("[%2d]DCACHE: Moving hit line to SB",id))
        end
      end

      ff_core_request.deq;
    `ifdef supervisor
      ff_from_tlb.deq;
    `endif
      if( lv_io_req && !lv_access_fault `ifdef supervisor && !pa_response.tlbmiss `endif ) begin
        //$display("[DCACHE ALLOC-IO] vaddr=%08x phyaddr=%08x access=%0d", 
        // req.address, phyaddr, req.access);
        `logLevel( dcache, 0, $format("[%2d]DCACHE: Allocating IO Buffer",id))
        m_iobuffer.ma_allocate_io(IoEntry{address: phyaddr, data: req.data, epoch:req.epochs,
                                          size: req.size, access: truncate(req.access)
                                          `ifdef atomic ,atomic_op: req.atomic_op `endif
                                          `ifdef supervisor 
                                              ,is_ptw_req: req.ptwalk_req 
                                              ,vaddr: req.address
                                          `endif 
                                    });
      end
    `ifdef supervisor
      if ( pa_response.tlbmiss) begin
        ff_hold_request.enq(ff_core_request.first);
        `logLevel( dcache, 0, $format("[%2d]DCACHE: Detected TLB Miss. parking current request", id))
      end
      else
    `endif
      if ((hit || lv_access_fault || lv_io_req `ifdef atomic || skip_op `endif ) ) begin
      `ifdef supervisor
        if (req.ptwalk_req)
          ff_ptw_response.enq(lv_response);
        else
      `endif
        ff_core_response.enq(lv_response);
        if(`drepl == 2 && (|lv_hitmask == 1) )
          replacement.update_set(set_index, fromOInt(unpack(lv_hitmask)));
        `logLevel( dcache, 0, $format("[%2d]DCACHE: Responding: ",id,fshow(lv_response)))
      end
      else begin  // Miss
        //$display("[DCACHE-MISS] phyaddr=%08x lv_io_req=%0d hit=%0d", 
             //phyaddr, pack(lv_io_req), pack(hit));
        let shift_amount = valueOf(TLog#(TDiv#(`dbuswidth,8)));
        Bit#(`paddr) blockmask = '1 << shift_amount;
        ff_mem_rd_request.enq(DCache_mem_readreq{ address   : phyaddr & blockmask,
                  burst_len  : fromInteger((v_blocksize/valueOf(TDiv#(`dbuswidth,`respwidth)))-1),
                  burst_size : fromInteger(valueOf(TLog#(TDiv#(`dbuswidth,8))))
                  });
        rg_miss_handling <= True;
        `logLevel( dcache, 0, $format("[%2d]DCACHE: MemReq: Sending Line Request for Addr:%h",id, phyaddr))
        Bool alldirty =  (&lv_set_valid == 1 && &lv_set_dirty == 1);
        Bool nonedirty = (&lv_set_valid == 1 && |lv_set_dirty == 0);
        Bool update_req = alldirty || nonedirty;
  	  	// capture all information required to handle a fill during a miss
  	  	MissMeta lv_miss_meta = MissMeta{ access: req.access,
  	  	                                  phy_addr: phyaddr,
  	  	                                  access_size: req.size,
    	  	                                epochs: req.epochs,
                                          sbid: m_storebuffer.mv_sb_tail
    	  	                              `ifdef supervisor
    	  	                                , req_is_ptw: req.ptwalk_req
    	  	                                , vaddr: req.address
    	  	                              `endif
    	  	                              `ifdef atomic
    	  	                                , atomic_op: req.atomic_op
    	  	                                ,wdata: req.data
    	  	                              `endif
    	  	                              };
        rg_miss_meta <= lv_miss_meta;
        rg_first <= True;
        rg_block_count <= pack(toOInt(lv_blocknum));
        rg_fill_err <= False;

        `logLevel( dcache, 0, $format("[%2d]DCACHE: Miss generated. Fetching line@Addr:%h",id,phyaddr))
      end

      `logLevel( dcache, 2, $format("[%2d]DCACHE: RAM Valid:%b Dirty:%b",id,lv_set_valid,lv_set_dirty))
      `logLevel( dcache, 0, $format("[%2d]DCACHE: ",id, fshow(lv_response)))
    endrule:rl_ram_check

    /*doc:rule: sends the evicted data from cache to the bus. This rule will fire only when
    * rg_eviction_required register is True. This rg_eviction_required is set by any one of the
    * following actions: a store-line-buffer release causing a replacement of a line, a fill line
    * release causing an replacement or a fence operation. 
    *
    * Also, when the rg_eviction_required is set to true, it is not necessary that in the immediate
    * cycle this rule fires. It may so happen that the ff_mem_wr_request fifo is full due to
    * contention on the lower memory or bus fabric. This may cause delays in this rule firing.
    * 
    * Thus, this rg_eviction is set to true, we prevent any of the rules performing the above sa id 
    * actions to fire. This is to prevent those rules from overwriting rg_eviction before the 
    * eviction has been performed.
    */
    rule rl_line_eviction(rg_eviction_required);
      rg_eviction_required <= False;
      `logLevel( dcache, 0, $format("[%2d]DCACHE: Performing eviction. rg_evict_addr:%h rg_evicted_line:%h", id, rg_evict_addr, rg_evicted_line))
      ff_mem_wr_request.enq(DCache_mem_writereq{address:rg_evict_addr,
                                            burst_len:fromInteger(valueOf(`dblocks)-1),
                                            burst_size:fromInteger(valueOf(TLog#(`dwords))),
                                            data: rg_evicted_line
                                        });
    endrule:rl_line_eviction

    /*doc:rule: This rule is used to move the line that was filled on a miss to the appropriate
    * place in the rams. This rule is fired immediately after receiving the last bytes of the line
    * from the lower memory. If no error was observed from the loewr memory for any bytes of the
    * line then we update the data and tag rams with the fill line in the way pointed by the
    * replacement module. 
    *
    * if all lines of the set are valid and dirty, then rg_fill_eviction will also be set during the
    * firing of this rule. In such a condition, we read the dirty line that is to be replaced and
    * send it for eviction.
    * 
    * When this rule fires, rule rl_ram_check cannot fire. However, if the set that was updated by
    * this rule is the same set that will be processed by the rl_ram_check in the subsequent cycle,
    * then we initiate a replay of the most recent core-request again on the rams to ensure the
    * updated write is observed while read from the rams.
    * 
    * This rule also preempts the rl_store_release rule below to ensure that the rams, whose lookup
    * was initiated in the previous cycle, read the rams and perform the eviction.
    */
    rule rl_fill_release(rg_fill_release && rg_miss_handling && !rg_eviction_required);
      rg_fill_release <= False;
      rg_miss_handling <= False;
      if (!rg_fill_err) begin
        `logLevel( dcache, 0, $format("[%2d]DCACHE: writing fill to ram tag:%h set:%d way:%d data:%h",id, 
          rg_fill_tag, rg_fill_set, rg_fill_way, pack(readVReg(v_fill_line))))
        m_data.ma_request_p2(rg_fill_set, pack(readVReg(v_fill_line)), rg_fill_way, '1);
        m_tag.ma_request_p2(rg_fill_set, rg_fill_way, {rg_fill_tag, 'd0});
        v_reg_valid[rg_fill_way][rg_fill_set] <= pack(!rg_fill_err);
        v_reg_dirty[rg_fill_way][rg_fill_set] <= 0;
      end
      if (rg_fill_eviction) begin
        let lv_line = m_data.mv_lineselect_p1(pack(toOInt(rg_fill_way))).line;
        Bit#(`tagbits) lv_tag <- m_tag.mv_select_p1(pack(toOInt(rg_fill_way)));
        Bit#(`paddr) lv_address = ?;
        lv_address = (v_setbits !=0 )? {lv_tag,rg_fill_set, 'd0} : {lv_tag, 'd0};
        rg_evict_addr <= lv_address;
        rg_evicted_line <= lv_line;
        rg_eviction_required <= True;
        rg_fill_eviction <= False;
        `logLevel( dcache, 0, $format("[%2d]DCACHE: Initiating eviction of dirty line replaced", id))
      end
      if ((rg_recent_req == rg_fill_set || rg_fill_eviction) && ff_core_request.notEmpty) begin
        rg_performing_replay[1] <= True;
      end
    endrule:rl_fill_release

    /*doc:rule: This rule is used to move the line from the store-line-buffer to the appropriate
    * place in the rams. This rule is fired when either : 

       - the store-line-buffer OR
       - fence is a pending operation and there is a valid entry in the store-line-buffer
       - there is a ready store-buffer-line for release and there is no pending request from the
         core
    * The rule updates the data and tag rams with store line at the head of the store-line-buffer to
    * the way pointed by the replacement module. 
    *
    * if all lines of the set are valid and dirty, then rg_store_eviction will also be set  in this
    * rule on its first iteration, thereby causing the rule to fire again. In the second round,
    * however, the dirty lines are read from the rams and sent for eviction while the new lines are
    * written.
    * 
    * When this rule fires, rule rl_ram_check cannot fire. However, if the set that was updated by
    * this rule is the same set that will be processed by the rl_ram_check in the subsequent cycle,
    * then we initiate a replay of the most recent core-request again on the rams to ensure the
    * updated write is observed while read from the rams.
    */
    rule rl_store_release(m_storebuffer.mv_release_head.release_ready && 
                          (m_storebuffer.mv_line_full || rg_fence_stall || !ff_core_request.notEmpty) &&
                          !m_storebuffer.mv_line_empty && !rg_eviction_required && 
                          !rg_performing_replay[1]);
      let lb_entry = m_storebuffer.mv_release_head;
      `logLevel( dcache, 0, $format("[%2d]DCACHE: Store release from entry:%d",id,m_storebuffer.mv_lb_head))
	    Bit#(TMax#(1, `setbits)) set_index = 0; 
	    if (v_setbits != 0) set_index = lb_entry.address[v_setbits+v_blockbits+v_wordbits-1:v_blockbits+v_wordbits];
      Bit#(`dways) lv_set_valid=?;
      Bit#(`dways) lv_set_dirty=?;
      for (Integer i = 0; i<`dways ; i = i + 1) begin
        lv_set_valid[i] = v_reg_valid[i][set_index];
        lv_set_dirty[i] = v_reg_dirty[i][set_index];
      end
      let waynum <- replacement.line_replace(set_index, lv_set_valid, lv_set_dirty);
      Bool alldirty =  (&lv_set_valid == 1 && &lv_set_dirty == 1);
      Bool nonedirty = (&lv_set_valid == 1 && |lv_set_dirty == 0);
      Bool update_req = alldirty || nonedirty;
      if (rg_store_eviction) begin
        let lv_line = m_data.mv_lineselect_p1(pack(toOInt(waynum))).line;
        Bit#(`tagbits) lv_tag <- m_tag.mv_select_p1(pack(toOInt(waynum)));
        Bit#(`paddr) lv_address= ?;
        if (v_setbits == 0) lv_address = {lv_tag,'d0}; else lv_address = {lv_tag, set_index, 'd0};
        `logLevel( dcache, 0, $format("[%2d]DCACHE: Store release staging for eviction:way:%d set:%d address:%h, line:%h",id, waynum, set_index, lv_address, lv_line))
        rg_evict_addr <= lv_address;
        rg_evicted_line <= lv_line;
        rg_eviction_required <= True;
        rg_store_eviction <= False;
      end
      if ( (lv_set_valid[waynum]&lv_set_dirty[waynum])==1 && !rg_store_eviction) begin
        wr_read_set_index <= set_index;
        rg_store_eviction <= True;
        `logLevel( dcache, 0, $format("[%2d]DCACHE: Store release initiating read for set:%d way:%d",id,set_index, waynum))
      end
      else begin
        v_reg_valid[waynum][set_index] <= 1;
        v_reg_dirty[waynum][set_index] <= 1;
        rg_global_dirty <= True;
        Bit#(TSub#(`paddr,TAdd#(`wordbits,`blockbits))) lv_tag = truncateLSB(lb_entry.address);
        m_data.ma_request_p2(set_index, lb_entry.line, waynum, '1);
        m_tag.ma_request_p2(set_index, waynum, truncateLSB(lb_entry.address));
        m_storebuffer.ma_release;
        `logLevel( dcache, 0, $format("[%2d]DCACHE: ",id, fshow(lb_entry), " to tag:%h set:%d way:%d",
          lv_tag, set_index, waynum))
        if ( (rg_recent_req == set_index || rg_store_eviction) && ff_core_request.notEmpty) begin
          rg_performing_replay[1] <= True;
        end
        if((`drepl == 1 && update_req) || (`drepl != 1)) begin// RR or PLRU
          replacement.update_set(set_index, waynum);
        end
      end
    endrule:rl_store_release
   
    /*doc:rule: This rule is fired when the most recent request from the core/ptw needs to be looked
     * up again on the rams, since a release operation may have corrupted the outputs of the rams.
    */
    rule rl_perform_replay(rg_performing_replay[0]);
      wr_read_set_index <= rg_recent_req;
      rg_performing_replay[0] <= False;
      `logLevel( dcache, 0, $format("[%2d]DCACHE: Performing replay for index:%d",id,rg_recent_req))
    endrule: rl_perform_replay

    /*doc:rule: This rule is fired when the core indicates that entry at the head of the io-buffer
     * can commit. This rule sends the io request to the bus directly*/
    rule rl_initiate_io(m_iobuffer.mv_io_head_valid && !io_empty && !rg_io_busy);
      let io_entry = m_iobuffer.mv_io_head;
      rg_io_busy <= True;
      ff_mem_io_request.enq(DCache_io_req{address: io_entry.address, data: io_entry.data,
                                      size: io_entry.size, read_write: io_entry.access == 1});
      `logLevel( dcache, 0, $format("[%2d]DCACHE: Initiating IO request: ",id,fshow(io_entry)))
    endrule:rl_initiate_io
   rule rl_show_dcache_blocked(sb_full || rg_fence_stall || rg_miss_handling || sb_busy);
    //$display("[DCACHE-BLOCKED] sb_busy=%0d replay=%0d miss=%0d fence=%0d sb_full=%0d",
       // pack(sb_busy), pack(rg_performing_replay[0]), pack(rg_miss_handling),
        //pack(rg_fence_stall), pack(sb_full));
endrule
    /*doc:rule: this rule waits for the response from the bus for a previous io requests. The
     * responses must occur in the same order as the requests were sent. The responses are then
     * realigned and sent to the core via the rg_core_io_response register. 
     * If an atomic operation is detected, then this rule will send out another write transaction
     * with the modified data and again wait for completion response which is then forwarded to the
     * core
    */
    rule rl_io_response(rg_io_busy);
      let io_entry = m_iobuffer.mv_io_head;
      let mem_response = ff_mem_io_resp.first();
      `logLevel( dcache, 0, $format("[%2d]DCACHE: IO Response from Bus",id,fshow(mem_response)))
	    Bit#(`wordbits) offset = truncate(io_entry.address);
	    mem_response.data = mem_response.data >> {offset,3'b0};
		  mem_response.data = case(io_entry.size)
		    'b000: signExtend(mem_response.data[7:0]);
		    'b001: signExtend(mem_response.data[15:0]);
		    'b010: signExtend(mem_response.data[31:0]);
  	  	'b100: zeroExtend(mem_response.data[7:0]);
  	  	'b101: zeroExtend(mem_response.data[15:0]);
  	  	'b110: zeroExtend(mem_response.data[31:0]);
  	  	default: mem_response.data;
		  endcase;
      ff_mem_io_resp.deq;
      Bit#(`causesize) lv_cause = io_entry.access == 0?`Load_access_fault:`Store_access_fault;
      let lv_response = DMem_core_response{word:mem_response.error?
                                        `ifdef supervisor truncate(io_entry.vaddr) `else zeroExtend(io_entry.address) `endif : 
                                         `ifdef atomic (io_entry.access == 2)? rg_atomic_rd_data: `endif mem_response.data, 
                                          trap: mem_response.error,
                                          entry_alloc: False,
                                          sb_id: ?,
                                          is_io: False, cause: lv_cause, epochs: io_entry.epoch
                                          `ifdef hypervisor ,gpa: ? `endif };
    `ifdef supervisor 
      if (io_entry.is_ptw_req) begin
          ff_ptw_response.enq(lv_response);
          m_iobuffer.ma_increment_head;
          rg_io_busy <= False;
      end
      else
    `endif
    `ifdef atomic
      if (io_entry.access==2 && !rg_io_atomic_done && !mem_response.error) begin
        let _new_store = fn_atomic_io_op(io_entry.atomic_op, io_entry.data, mem_response.data);
        rg_io_atomic_done <= True;
        rg_atomic_rd_data <= mem_response.data;
        ff_mem_io_request.enq(DCache_io_req{address: io_entry.address, data: _new_store,
                                      size: io_entry.size, read_write: True});
        `logLevel( dcache, 0, $format("DACCHE[%2d]: IO Atomic Rd phase Done. NewSt:%h",id, _new_store))
      end
      else if (io_entry.access == 2 && rg_io_atomic_done) begin
        rg_io_atomic_done <= False;
        m_iobuffer.ma_increment_head();
        rg_io_busy <= False;
        rg_core_io_response <= tagged Valid (lv_response);
        `logLevel( dcache, 0, $format("DACCHE[%2d]: IO Atomic Wr phase Done.",id))
      end
      else
    `endif
      begin
        rg_core_io_response <= tagged Valid  (lv_response);
        m_iobuffer.ma_increment_head;
        rg_io_busy <= False;
      end
    endrule:rl_io_response

    /*doc:rule: This rule is responsible for collecting the bytes of a missing line from the lower
     * memory. This rule however is blocked when a store-release is happening. 
     * In case of a load/atomic operation, when the first word arrives, we realign and send it back to the
     * core/ptw as a response. In case of a store however, we wait for all the bytes to arrive and
     * update the store-line-buffer before responding to the core. 
     * 
     * This is because when the core is responded on the first byte, it may move ahead and initiate
     * a commit of the storebuffer entry into the line. However, the line is not yet allocated in
     * the store-line-buffer there by preventing the commit from happening.
     *
     * Once the last byte arrives the line is either sent to the store buffer (in case of
     * store/atomic ops) or else a fill line eviction is initiated. If the line in the ram that is
     * going to be updated is going to be written to, then we initiate the lookup of that line in
     * rams in this rule itself.
     *
     * As long as rg_miss_handling is set, the cache cannot process or accept any new requests
     * (thereby preventing rule rl_ram_check and receive_core_req methods from firing simultaneously
     * with this rule.
     *
     * Once must note, that we expect the data to arrive in a wrap-around fashion i.e. that
     * requested word of the line must arrive first. The rule maintain a counter to indicate which
     * bytes of the line should be updated by the current response from the lower memory.
     * 
     * if an error was received while fetching the requested the word, the error is forwarded tothe
     * core/ptw as an appropriate access fault. However, if an error was requested while receiving
     * non-requested bytes of the line, then the fill is prevented from writing a line into the
     * rams. Thus subsequent accesses to the same requested word will be treated as line-misses and
     * the same behvaior will be reproduced.
    */
    rule rl_fill_from_memory(rg_miss_handling && 
                             !rg_performing_replay[0]);
      let resp = ff_mem_rd_resp.first();
      ff_mem_rd_resp.deq();
      `logLevel( dcache, 0, $format("[%2d]DCACHE: fill from mem:",id,fshow(resp)))
	    Bit#(`dblocks) rotator = rg_block_count;
	    Bit#(TMax#(1, `setbits)) set_index = 0; 
	    if (v_setbits != 0) set_index = rg_miss_meta.phy_addr[v_setbits+v_blockbits+v_wordbits-1:v_blockbits+v_wordbits];
	    Bit#(`blockbits) block_index = rg_miss_meta.phy_addr[v_blockbits+v_wordbits-1:v_wordbits];
	    Bit#(`tagbits) request_tag = truncateLSB(rg_miss_meta.phy_addr);
	    Vector#( `dblocks, Bit#(`respwidth) ) lv_line = readVReg(v_fill_line);
  	  let lv_bus_err = rg_fill_err || resp.err;

      lv_line[fromOInt(unpack(rg_block_count))] = resp.data;
      Bit#(`dways) lv_set_valid=?;
      Bit#(`dways) lv_set_dirty=?;
      for (Integer i = 0; i<`dways ; i = i + 1) begin
        lv_set_valid[i] = v_reg_valid[i][set_index];
        lv_set_dirty[i] = v_reg_dirty[i][set_index];
      end
      let lv_way_replacement <- replacement.line_replace(set_index, lv_set_valid, lv_set_dirty);

	    Bit#(`causesize) lv_cause = rg_miss_meta.access!=0 ? `Store_access_fault: `Load_access_fault;

      resp.data = fn_realign_n_update(rg_miss_meta.phy_addr, rg_miss_meta.access_size, resp.data);
      Bit#(`paddr) _t = 0;
      let lv_response = DMem_core_response{word: resp.data, 
                                          trap: resp.err,
                                          is_io: False, 
                                          sb_id: rg_miss_meta.sbid,
                                          cause: lv_cause, 
                                          epochs: rg_miss_meta.epochs,
                                          entry_alloc: rg_miss_meta.access != 0
                                          `ifdef hypervisor ,gpa: _t `endif };

      if (resp.err)
        lv_response.word = rg_miss_meta.vaddr;
    `ifdef atomic
      if (rg_miss_meta.access == 2 && rg_miss_meta.atomic_op == 'b0111)
        lv_response.word = 0;
    `endif

      if( (rg_first && rg_miss_meta.access == 0) || 
          (rg_miss_meta.access == 1 && resp.last) 
        `ifdef atomic || (rg_first && rg_miss_meta.access == 2) `endif 
        ) begin
        rg_first <= False;
        `logLevel( dcache, 0, $format("[%2d]DCACHE: fwd fill response to core:",id,fshow(lv_response)))
      `ifdef supervisor
        if (rg_miss_meta.req_is_ptw)
          ff_ptw_response.enq(lv_response);
        else
      `endif
        ff_core_response.enq(lv_response);
      `ifdef atomic
        if (rg_miss_meta.access == 2)
          m_storebuffer.ma_perform_atomic(rg_miss_meta.atomic_op, lv_response.word, rg_miss_meta.wdata, 
                                         rg_miss_meta.sbid);
      `endif
      end
      Bool alldirty =  (&lv_set_valid == 1 && &lv_set_dirty == 1);
      Bool nonedirty = (&lv_set_valid == 1 && |lv_set_dirty == 0);
      Bool update_req = alldirty || nonedirty;

      if (resp.last) begin
        rg_fill_tag <= request_tag;
        rg_fill_set <= set_index;
        rg_fill_way <= lv_way_replacement;
        if (rg_miss_meta.access !=0 && !lv_bus_err) begin
          m_storebuffer.ma_allocate_line(rg_miss_meta.phy_addr, pack(lv_line));
          rg_miss_handling <= False;
        end
        else begin
          rg_fill_release <= True;
          if ( (lv_set_valid[lv_way_replacement]&lv_set_dirty[lv_way_replacement])==1) begin
            wr_read_set_index <= set_index;
            rg_fill_eviction <= True;
          end
          if((`drepl == 1 && update_req) || (`drepl != 1)) begin// RR or PLRU
            replacement.update_set(set_index, lv_way_replacement);
          end
        end
      end
		  rg_fill_err <= lv_bus_err;
		  rotator = rotateBitsBy(unpack(rotator), 1);
		  rg_block_count <= rotator;
		  writeVReg(v_fill_line, lv_line);
		  `logLevel( dcache, 0, $format("[%2d]DCACHE: fill rotator:%b",id,rotator))
    endrule:rl_fill_from_memory

    /*
    This method receives a new request from the core or the ptw. If its a fence request from the
    core, then the no more subsequent requests are taken until all the lines have cleaned by the
    fence operation.
    This method also updates the rg_recent_req register with the set being accessed. This is used by
    the the release action rules to decide if a replay of the request needs to be performed due to
    updates/accesses in the rams.
    */
    interface receive_core_req=interface Put
      method Action put(DCache_core_request#(`vaddr,`respwidth,`desize) req)
          if(!sb_busy && !rg_performing_replay[0] && !rg_miss_handling && !rg_fence_stall && !sb_full && !ff_mem_wr_request.notEmpty);
          
      `ifdef perfmonitors
          if(req.access == 0)
            wr_total_read_access <= 1;
          if(req.access == 1)
            wr_total_write_access <= 1;
        `ifdef atomic
          if(req.access == 2)
            wr_total_atomic_access <= 1;
        `endif
      `endif
        Bit#(`paddr) phyaddr = truncate(req.address);
        Bit#(TMax#(1, `setbits)) set_index=0;
        if (v_setbits != 0) set_index = req.fence?0:phyaddr[v_setbits+v_blockbits+v_wordbits-1:v_blockbits+v_wordbits];
        ff_core_request.enq(req);
        rg_fence_stall<=req.fence;
        if(wr_cache_enable) begin
          wr_read_set_index <= set_index;
        end
        rg_recent_req <= set_index;
        `logLevel( dcache, 0, $format("[%2d]DCACHE: Receiving request: ",id,fshow(req), " set:%d",set_index))
      endmethod
    endinterface;



    /*this method is used to indicate that a particular entry in the store-buffer is ready for
     * commit*/
    method ma_commit_store = m_storebuffer.ma_commit_store;

    /*this method indicates that the head of the io-buffer can start its operations*/
    method Action ma_commit_io(Bit#(`desize) currepoch);
     //$display("[DCACHE COMMIT] epoch_match=%b", io_entry.epoch == currepoch);
    `ifdef ASSERT
      dynamicAssert(!m_iobuffer.mv_io_head_valid,"IO Head is already ready to commit.");
    `endif
      let io_entry = m_iobuffer.mv_io_head;
      `logLevel( dcache, 0, $format("[%2d]DCACHE: Commit IO entry:",id,fshow(io_entry)))
      if(io_entry.epoch == currepoch) begin
        m_iobuffer.ma_commit_io();
      end
      else begin
        `logLevel( dcache, 0, $format("[%2d]DCACHE: IO is being dropped- epoch mismatch",id))
        m_iobuffer.ma_increment_head;
      end

    endmethod

    /*method to accept if the cache is enabled or not*/
    method Action ma_cache_enable(Bool c);
      wr_cache_enable <= c;
    endmethod

    /*method to accept the current privilege mode under which operations are to be performed*/
    // method Action ma_curr_priv (Bit#(2) c);
    //   wr_priv <= c;
    // endmethod

    interface send_mem_rd_req = toGet(ff_mem_rd_request);
    interface receive_mem_rd_resp = toPut(ff_mem_rd_resp);

    interface send_core_cache_resp = toGet(ff_core_response);
    method send_core_io_resp = rg_core_io_response;

    interface send_mem_io_req = toGet(ff_mem_io_request);
    interface receive_mem_io_resp = toPut(ff_mem_io_resp);

    method send_mem_wr_req = ff_mem_wr_request.first;
    method Action deq_mem_wr_req;
      ff_mem_wr_request.deq;
    endmethod
    interface receive_mem_wr_resp = toPut(ff_mem_wr_resp);
  `ifdef supervisor
    interface get_ptw_resp = toGet(ff_ptw_response);
    interface put_pa_from_tlb = toPut(ff_from_tlb);
    interface get_hold_req = toGet(ff_hold_request);
  `endif
  `ifdef perfmonitors
    method mv_perf_counters = {wr_total_read_access , wr_total_write_access , wr_total_atomic_access
                          , wr_total_io_reads , wr_total_io_writes , wr_total_read_miss ,
                            wr_total_write_miss , wr_total_atomic_miss , 'd0, wr_total_evictions };
  `endif
    method mv_storebuffer_empty = sb_empty;
    method mv_cache_available = ff_core_response.notFull && ff_core_request.notFull &&
        !rg_fence_stall && !sb_full && !rg_eviction_required && !rg_miss_handling &&
        !rg_performing_replay[0] && !sb_busy && !io_full && !ff_mem_wr_request.notEmpty
        `ifdef dcache_ecc && !rg_perform_sec && !rg_halt_ram_check `endif ;
  `ifdef dcache_ecc
    method mv_ded_data = wr_ded_data_log;
    method mv_sed_data = wr_sed_data_log;
    method mv_ded_tag = wr_ded_tag_log;
    method mv_sed_tag = wr_ded_tag_log;
    method Action ma_ram_request(DRamAccess access)if(!rg_fence_stall);
      Bit#(blocksize) _banks = 0;
      _banks[access.banks] = 1;
      if(!access.tag_data) begin // access tag;
        m_tag.ma_request_p2(access.read_write, access.index, truncate(access.data), access.way);
      end
      else begin
        m_data.ma_request_p2(access.read_write, access.index, duplicate(access.data) , access.way,
        _banks);
      end
      rg_access_req <= tagged Valid access;
    endmethod
    method Bit#(`respwidth) mv_ram_response if(!rg_fence_stall 
                                              &&& rg_access_req matches tagged Valid .access);
      Bit#(`respwidth) tag_response = zeroExtend(m_tag.mv_sideband_read(access.way));
      Bit#(`respwidth) data_response = m_data.mv_sideband_read(access.way,
                                        access.banks);
      if(!access.tag_data) // access tag
        return tag_response;
      else
        return data_response;
    endmethod
  `endif
  endmodule:mkdcache

endpackage:dcache1r1w

