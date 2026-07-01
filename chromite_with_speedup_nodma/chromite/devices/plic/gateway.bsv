// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd.
// see LICENSE.incore for more details on licensing terms
/*
Author: Babu P S , babu.ps@incoresemi.com
Created on: Thursday 20 May 2021 11:04:16 AM IST

*/
import Clocks         :: * ;
import FIFOF          :: * ;
import SpecialFIFOs   :: * ;

interface Ifc_gateway2;
  (*always_ready, always_enabled*)
  method Action ma_complete();
  (*always_ready, always_enabled*)
  method Action ma_clear();
  (*always_ready*)
  method Bit#(1) mv_interrupt();
  (*always_ready, always_enabled*)
  method Action ma_input(Bit#(1) in);
endinterface:Ifc_gateway2

module mk_gateway2#(parameter Integer capture_sz, Clock src_clock, Reset src_rst, Bit#(1) level_edge, Bit#(1) activity)
                   (Ifc_gateway2);

  let curr_clk <- exposeCurrentClock;
  Bool sync_required = (curr_clk != src_clock);

  /*doc:reg: */
  Reg#(Bit#(1)) rg_in1 <- mkReg(0, clocked_by src_clock, reset_by src_rst);
  /*doc:reg: */
  Reg#(Bit#(1)) rg_in2 <- mkReg(0, clocked_by src_clock, reset_by src_rst);

  FIFOF#(void) ff_interrupt <- mkUGSizedFIFOF(capture_sz);

  let rise_int_pending = rg_in2 & ~rg_in1;
  let fall_int_pending = ~rg_in2 & rg_in1;
  
  /*doc:rule: */
  rule rl_delayed_inputs;
    rg_in2 <= rg_in1;
  endrule:rl_delayed_inputs

  if (sync_required ) begin
    SyncBitIfc#(Bit#(1)) sync_interrupt <- mkSyncBitToCC(src_clock, src_rst);

    /*doc:rule: */
    rule rl_capture_sync_interrupt;
      if (level_edge == 0 && rg_in1 == activity && rg_in2 != rg_in1) // level interrupts
        sync_interrupt.send(1);
      else if (level_edge == 1 && ((rise_int_pending==1 && activity==1) ||  // edge triggered
                                 (fall_int_pending==1 && activity == 0) ))
        sync_interrupt.send(1);
    endrule:rl_capture_sync_interrupt
    rule rl_latch_interrupt(sync_interrupt.read == 1);
      ff_interrupt.enq(?);
    endrule:rl_latch_interrupt
  end
  else begin
    /*doc:rule: */
    rule rl_capture_interrupt;
      if (level_edge == 0 && rg_in1 == activity && !ff_interrupt.notEmpty) // level interrupts
        ff_interrupt.enq(?);
      else if (level_edge == 1 && ((rise_int_pending==1 && activity==1) ||  // edge triggered
                                 (fall_int_pending==1 && activity == 0) ))
        ff_interrupt.enq(?);
    endrule:rl_capture_interrupt
  end

  /*doc:rule: */
  method Action ma_complete();
    if (ff_interrupt.notEmpty)
    ff_interrupt.deq();
  endmethod:ma_complete

  method Action ma_clear();
    ff_interrupt.clear();
  endmethod:ma_clear

  method mv_interrupt = pack(ff_interrupt.notEmpty);
  method Action ma_input(Bit#(1) in);
    rg_in1 <= in;
  endmethod:ma_input

endmodule:mk_gateway2
interface Ifc_gateway#(numeric type sources);
    (*always_ready , always_enabled*)
    method Bit#(sources) get_irq;
endinterface

import "BVI" gateway =
module mk_gateway  #( Bit#(sources) src , /* Bit#(sources) clk_bit,*/ Bit#(sources) actv_low,
                     Bit#(sources) complete `ifdef gateway_le_detect , Bit#(sources) l0e1 `endif )
      (Ifc_gateway#(sources)) provisos(Add#(1, _a, sources));

    parameter width = valueOf(sources);

    default_clock xclk (CLK_BIT, (*unused*) CLK_GATE) <- exposeCurrentClock;
    default_reset rst (RST) clocked_by(xclk)          <- exposeCurrentReset;

    //port CLK_BIT    = xclk;
    port SRC      clocked_by(xclk)      = src;
    port COMPLETE clocked_by(no_clock)  = complete;
    port ACTV_LOW  = actv_low;
`ifdef gateway_le_detect
    port L0E1      = l0e1;
`endif

    method (*reg*)Q_OUT get_irq clocked_by(no_clock) reset_by(no_reset);

    schedule get_irq CF get_irq;

endmodule
