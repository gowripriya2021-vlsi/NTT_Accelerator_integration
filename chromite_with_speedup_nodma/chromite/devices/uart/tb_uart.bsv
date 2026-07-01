// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Friday 24 April 2020 11:39:53 AM IST

*/
package tb_uart ;
import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;

`include "Logger.bsv"

import uart         :: * ;
import apb          :: * ;
import StmtFSM      :: * ;
import DCBus        :: * ;
import Connectable  :: * ;
import Semi_FIFOF   :: * ;
import RS232_modified      :: * ;

`define datasize 32
`define depth 16
`define initbaud 1
`define paddr 20
`define base 'h11300

(*synthesize*)
module mkinst_uartapb(Ifc_uart_apb#(`paddr, `datasize, 0, `depth));
	let core_clock<-exposeCurrentClock;
	let core_reset<-exposeCurrentReset;
  let ifc();
  mkuart_apb#(`initbaud, `base, core_clock, core_reset) _temp(ifc);
  return ifc;
endmodule:mkinst_uartapb


module mkTb(Empty);
  let mod <- mkinst_uartapb;
  /*doc:reg: */
  Reg#(Bit#(32)) rg_count <- mkReg(0);
  Reg#(int) iter <- mkRegU;

  Reg#(Bit#(32)) rg_inp_val <-mkReg('h0);

  Ifc_apb_master_xactor#(`paddr,`datasize,0) master <- mkapb_master_xactor;
  mkConnection(master.apb_side,mod.slave);
  Reg#(Bool) rg_tx_done <- mkReg(False);
  Reg#(Bool) rg_rx_ready <- mkReg(False);
  
  Stmt print_incore= (
    seq
      master.fifo_side.i_request.enq(APB_request {paddr:`base + 'h04, pwdata: 'h49, pwrite: True, pstrb:'h01});
      action
        await (master.fifo_side.o_response.notEmpty);
        master.fifo_side.o_response.deq;
        if(master.fifo_side.o_response.first.pslverr) begin $display("ERROR on Access"); $finish(0); end
      endaction
      master.fifo_side.i_request.enq(APB_request {paddr:`base + 'h04, pwdata: 'h6d, pwrite: True, pstrb:'h01});
      action
        await (master.fifo_side.o_response.notEmpty);
        master.fifo_side.o_response.deq;
        if(master.fifo_side.o_response.first.pslverr) begin $display("ERROR on Access"); $finish(0); end
      endaction
      master.fifo_side.i_request.enq(APB_request {paddr:`base + 'h04, pwdata: 'h43, pwrite: True, pstrb:'h01});
      action
        await (master.fifo_side.o_response.notEmpty);
        master.fifo_side.o_response.deq;
        if(master.fifo_side.o_response.first.pslverr) begin $display("ERROR on Access"); $finish(0); end
      endaction
      master.fifo_side.i_request.enq(APB_request {paddr:`base + 'h04, pwdata: 'h6f, pwrite: True, pstrb:'h01});
      action
        await (master.fifo_side.o_response.notEmpty);
        master.fifo_side.o_response.deq;
        if(master.fifo_side.o_response.first.pslverr) begin $display("ERROR on Access"); $finish(0); end
      endaction
      master.fifo_side.i_request.enq(APB_request {paddr:`base + 'h04, pwdata: 'h72, pwrite: True, pstrb:'h01});
      action
        await (master.fifo_side.o_response.notEmpty);
        master.fifo_side.o_response.deq;
        if(master.fifo_side.o_response.first.pslverr) begin $display("ERROR on Access"); $finish(0); end
      endaction
      master.fifo_side.i_request.enq(APB_request {paddr:`base + 'h04, pwdata: 'h65, pwrite: True, pstrb:'h01});
      action
        await (master.fifo_side.o_response.notEmpty);
        master.fifo_side.o_response.deq;
        if(master.fifo_side.o_response.first.pslverr) begin $display("ERROR on Access"); $finish(0); end
      endaction
      while(!rg_tx_done)
      seq
        master.fifo_side.i_request.enq(APB_request {paddr:`base + 'h0c, pwdata: ?, pwrite: False, pstrb:'1});
        action
          await (master.fifo_side.o_response.notEmpty);
          master.fifo_side.o_response.deq;
          if(master.fifo_side.o_response.first.pslverr) begin $display("ERROR on Access"); $finish(0); end
          if(master.fifo_side.o_response.first.prdata[0] == 1) begin $display("TX DONE");rg_tx_done <= True; end
        endaction
      endseq
      while(rg_tx_done)
      seq
        master.fifo_side.i_request.enq(APB_request {paddr:`base + 'h0c, pwdata: ?, pwrite: False, pstrb:'1});
        action
          await (master.fifo_side.o_response.notEmpty);
          master.fifo_side.o_response.deq;
          if(master.fifo_side.o_response.first.pslverr) begin $display("ERROR on Access"); $finish(0); end
          if(master.fifo_side.o_response.first.prdata[3] == 1) begin $display("RX Ready"); rg_rx_ready <= True; end
        endaction
        master.fifo_side.i_request.enq(APB_request {paddr:`base + 'h08, pwdata: ?, pwrite: False, pstrb:'1});
        action
          if (rg_rx_ready) begin
              await (master.fifo_side.o_response.notEmpty);
              master.fifo_side.o_response.deq;
              rg_rx_ready <= False;
              if(master.fifo_side.o_response.first.pslverr) begin $display("ERROR on Access"); $finish(0); end
              if(master.fifo_side.o_response.first.prdata == 'h65) begin 
                $display("PASSED");
                $finish(0); 
              end
              `logLevel( tb, 0, $format("Received Char:",master.fifo_side.o_response.first.prdata))
          end
        endaction
      endseq
    endseq
  );

  /*doc:rule: */
  rule rl_create_loopback;
    mod.device.io.sin(mod.device.io.sout);
    `logLevel( tb, 0, $format(""))
  endrule
  mkAutoFSM(seq
    print_incore;
    $finish(0);
  endseq);

endmodule
endpackage: tb_uart

