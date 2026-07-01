/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved. See LICENSE.incore for more details.
  Created On:  Tue Jan 18, 2022 19:52:14 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks
*/

package prefetch;
  `include "Logger.bsv"
`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import FIFO :: * ;
  import FIFOF :: * ;
  import SpecialFIFOs :: * ;
  import Vector :: * ;
  import GetPut :: * ;
  import Assert  :: * ;
  import OInt :: * ;
  import BUtils :: * ;
  import DReg :: * ;
  import ConfigReg :: * ;
  import icache_types::*;

  typedef struct{
    Bool hit;
    Bool rdy;
    Bit#(linewidth) data;
    Bit#(1) err;
  } Prefetch_lookup#(linewidth) deriving {Bits,Eq,FShow};

  interface Ifc_prefetch#(numeric type paddr,
      numeric type linewidth,
      numeric type buswidth,
      numeric type size);
    method Action ma_miss(Bit#(paddr) address);
    method Prefetch_lookup#(linewidth,size) mv_lookup(Bit#(paddr) address);
    method Action ma_deq_head;
    method Maybe#(Bit#(paddr)) mv_pending_request;
    method Action ma_from_mem(ICache_mem_readresp#(buswidth) req);
  endinterface: Ifc_prefetch

  module mk_iprefetch#(parameter Bit#(32) id, parameter Bool onehot)
      (Ifc_prefetch#(paddr,linewidth,buswidth,size))
      provisos(
        Div#(linewidth,buswidth,blocksize),
        Sub#(paddr,TLog#(linewidth),sz_prefix)
  );
    Vector#(size,Vector#(blocksize,ConfigReg#(Bit#(respwidth)))) v_rg_data
                                                  <- replicateM(replicateM(mkConfigReg(unpack(0))));
    Vector#(size,ConfigReg#(Bit#(1))) v_rg_err <- replicateM(mkConfigReg(0));
    Vector#(size,ConfigReg#(Bit#(1))) v_rg_addr_valid <- replicateM(mkConfigReg(0));
    Vector#(size,ConfigReg#(Bit#(1))) v_rg_valid_flag <- replicateM(mkConfigReg(0));
    Vector#(size,Reg#(Bit#(sz_prefix))) v_rg_addr     <- replicateM(mkReg(0));

    Reg#(Bit#(sz_prefix)) rg_stream_addr[3] <- mkCReg(3,0);
    Reg#(Bool) rg_stream_valid <- mkReg(False);
    Reg#(Bool) rg_stream_pause <- mkReg(False);
    Reg#(Bool) rg_wait_mem <- mkReg(False);
    Reg#(Bool) rg_inc <- mkReg(False);

    Reg#(Bit#(TLog#(size))) rg_head     <- mkReg(0);
    Reg#(Bit#(TLog#(size))) rg_tail     <- mkReg(0);
    Reg#(Bit#(TLog#(blocksize))) rg_next_bank<- mkReg(0);

    Wire#(Bool) wr_miss <- mkDWire(False);

    method Action ma_miss(Bit#(paddr) address);
      Bit#(sz_prefix) prefix = truncateLSB(address);
      rg_stream_addr[2] <= prefix;
      v_rg_addr[0] <= prefix;
      v_rg_addr_valid[0] <= 1;
      rg_tail <= 0;
      rg_head <= 0;
      wr_miss <= True;
      rg_stream_valid <= True;
      rg_stream_pause <= False;
      rg_wait_mem <= False;
      for(Integer i=0;i<valueof(size);i=i+1) begin
        v_rg_valid_flag[i] <= 0;
        v_rg_err[i] <= 0;
      end
    endmethod

    method Action ma_from_mem(ICache_mem_readresp#(buswidth) req);
      if(rg_wait_mem) begin
        let lv_err = v_rg_err[rg_tail] & pack(req.err);
        v_rg_data[rg_tail][rg_next_bank] <= req.data;
        v_rg_err[rg_tail] <= lv_err;
        rg_next_bank <= rg_next_bank + 1;
        if(req.last) begin
          rg_wait_mem <= False;
          v_rg_valid_flag[rg_tail] <= 1;
          if(!lv_err)
            rg_stream_addr <= rg_stream_addr + 1;      
          else
            rg_stream_pause <= True;
        end
      end
    endmethod

    method Maybe#(Bit#(paddr)) mv_pending_request;
      if(rg_stream_valid && !rg_stream_pause && rg_tail != (rg_head-1) && !rg_mem_wait) begin
        let _idx = (rg_tail == valueof(size)-1)? 0: rg_tail + 1;
        if(!unpack(v_rg_addr_valid[rg_tail] & v_rg_valid_flag[rg_tail])) begin
          rg_tail <= idx;
          v_rg_addr_valid[idx] <= 1;
          v_rg_addr[idx] <= rg_stream_addr;
        end
        rg_mem_wait <= True;
        rg_next_bank <= 0;
        return tagged Valid {rg_stream_addr,0};
      end
      else 
        return tagged Invalid;
    endmethod

    method Prefetch_lookup#(linewidth) mv_lookup(Bit#(paddr) address);
      return Prefetch_lookup{
        data: v_rg_data[rg_head],
        hit: v_rg_addr_valid[rg_head] == 1 && (v_rg_addr[rg_head] == truncate(address)),
        rdy: v_rg_valid_flag[rg_head],
        err: v_rg_err[rg_head]
      };
    endmethod
    method Action ma_deq_head;
      if(rg_stream_valid) begin
        let lv_only_one = rg_head == rg_tail;
        if(lv_only_one || rg_head == valueof(size)-1) begin
          rg_head <= 0;
        end
        else
          rg_head <= rg_head + 1;
        v_rg_addr_valid[rg_head] <= 0;
        v_rg_valid_flag[rg_head] <= 0;
        if(lv_only_one)
          rg_tail <= 0;
      end
    endmethod


  endmodule
  

endpackage: prefetch
