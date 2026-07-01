// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Thursday 23 April 2020 09:15:50 PM IST

*/
package tb_gpio;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;

`include "Logger.bsv"
import gpio         :: * ;
import apb          :: * ;
import StmtFSM      :: * ;
import DCBus        :: * ;
import Connectable  :: * ;
import Semi_FIFOF   :: * ;


`define datasize 32
`define ionum 32
`define interrupt_size 20
`define base 'h550
`define paddr 16

(*synthesize*)
module [Module] mkinst_gpioapb(Ifc_gpio_apb#(`paddr, `datasize, 0, `ionum, `interrupt_size));
  let clk <- exposeCurrentClock;
  let rst <- exposeCurrentReset;
  let ifc();
  mkgpio_apb#(`base, clk, rst) _temp(ifc);
  return ifc;
endmodule:mkinst_gpioapb

module mkTb(Empty);
  let mod <- mkinst_gpioapb;
  /*doc:reg: */
  Reg#(Bit#(32)) rg_count <- mkReg(0);
  Reg#(int) iter <- mkRegU;

  Reg#(Bit#(`ionum)) rg_inp_val <-mkReg('h0);

  Ifc_apb_master_xactor#(`paddr,`datasize,0) master <- mkapb_master_xactor;
  mkConnection(master.apb_side,mod.slave);

  `include "tb_common.bsv"

  Stmt rise_interrupt = (
    seq
      fn_send_write(`base + 'h18,'hff,'1);
      delay(3);
      rg_inp_val <= 'hffff;
      delay(10);
      if(mod.device.sb_gpio_to_plic != 'hff) par $display("FAIL: Rise Interrupt Failed"); $finish(0); endpar
      fn_fail_on_apb_error(1);
    endseq
  );
  Stmt fall_interrupt = (
    seq
      fn_send_write(`base + 'h20,'hff00,'1);
      delay(3);
      rg_inp_val <= 'h00ff;
      delay(10);
      if(mod.device.sb_gpio_to_plic != 'hffff) par $display("FAIL: Fall Interrupt Failed"); $finish(0); endpar
      fn_fail_on_apb_error(2);
    endseq
  );
  Stmt clear_rise_interrupt = (
    seq
      fn_send_write(`base + 'h1c,'h00ff,'1);
      delay(3);
      if(mod.device.sb_gpio_to_plic != 'hff00) par $display("FAIL: Rise Interrupt Clearing Failed"); $finish(0); endpar
      fn_fail_on_apb_error(3);
    endseq
  );
  Stmt clear_fall_interrupt = (
    seq
      fn_send_write(`base + 'h20,'hff00,'1);
      delay(3);
      if(mod.device.sb_gpio_to_plic != 'h0000) par $display("FAIL: Fall Interrupt Clearing Failed"); $finish(0); endpar
      fn_fail_on_apb_error(4);
    endseq
  );

  Stmt access_errors = (
    seq
      fn_send_read(`base + 0);
      fn_fail_on_apb_error(0);
      fn_send_write(`base + 'h0,'hffff,'1);
      fn_pass_on_apb_error(1);
      fn_send_write(`base + 'h2,'hffff,'1);
      fn_pass_on_apb_error(2);
      fn_send_write(`base + 'h8,'hffff,'1);
      fn_fail_on_apb_error(3);
      fn_send_write(`base + 'h8,'hbeef,'b10);
      fn_fail_on_apb_error(4);
      fn_send_read(`base + 'h8);
      fn_fail_on_apb_error(4);
    endseq
  );

  mkAutoFSM(seq
    rise_interrupt;
    $display("TEST1 PASSED >>>>>>>>>>>>>>");
    fall_interrupt;
    $display("TEST2 PASSED >>>>>>>>>>>>>>");
    clear_rise_interrupt;
    $display("TEST3 PASSED >>>>>>>>>>>>>>");
    clear_fall_interrupt;
    $display("TEST4 PASSED >>>>>>>>>>>>>>");
    access_errors;
    $display("TEST5 PASSED >>>>>>>>>>>>>>");
    $finish(0);
  endseq);


  /*doc:rule: */
  rule rl_drive_inputs;
    mod.device.io.gpio_in_val(bits2vec(rg_inp_val));
  endrule

  /*doc:rule: */
  rule rl_read_outputs;
		`logLevel( tb, 0, $format(""))
    `logLevel( tb, 0, $format("gpio_interrupt  :%h",mod.device.sb_gpio_to_plic))
  endrule
endmodule:mkTb

endpackage:tb_gpio

