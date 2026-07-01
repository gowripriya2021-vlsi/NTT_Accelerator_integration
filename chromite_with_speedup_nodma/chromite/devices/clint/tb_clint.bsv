// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Friday 24 April 2020 08:49:58 PM IST

*/
package tb_clint;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;

  `include "Logger.bsv"
  import clint        :: * ;
  import apb          :: * ;
  import DCBus        :: * ;
  import StmtFSM      :: * ;
  import Connectable  :: * ;
  import Semi_FIFOF   :: * ;

`define datasize 32
`define msip_size 1
`define tick_count 4
`define timecmp_reset_val '1
`define base 'hc0000000
`define paddr 32

(*synthesize*)
module [Module] mkinst_clintapb(Ifc_clint_apb#(`paddr, `datasize, 0, `tick_count, `msip_size));
  let clk <- exposeCurrentClock;
  let rst <- exposeCurrentReset;
  let ifc();
  mkclint_apb#(`timecmp_reset_val, `base, clk, rst) _temp(ifc);
  return ifc;
endmodule:mkinst_clintapb

module mkTb(Empty);
  let mod <- mkinst_clintapb;
  /*doc:reg: */
  Reg#(Bit#(32)) rg_count <- mkReg(0);
  Reg#(int) iter <- mkRegU;

  Ifc_apb_master_xactor#(`paddr,`datasize,0) master <- mkapb_master_xactor;
  mkConnection(master.apb_side,mod.slave);
  
  `include "tb_common.bsv"

  Stmt gen_msip = (
  seq
    // check if msip is clear
    fn_send_read(`base + 'h0);
    fn_checknfail_on_apb_error(1,'h0);
    
    // set msip
    fn_send_write(`base + 'h0,'b1,'b1);
    fn_fail_on_apb_error(2);

    // check msip is high
    fn_send_read(`base + 'h0);
    fn_checknfail_on_apb_error(3,'h1);
    action
      if(mod.device.sb_clint_msip != 1) begin $display("MSIP Failed. Expect sb_clint_msip = 1");
        $finish(0); end
    endaction

    // reset msip
    fn_send_write(`base + 'h0,'b0,'b1);
    fn_fail_on_apb_error(4);

    fn_send_read(`base + 'h0);
    fn_checknfail_on_apb_error(5,'h0);
    action
      if(mod.device.sb_clint_msip != 0) begin $display("MSIP Failed. Expect sb_clint_msip = 0");
        $finish(0); end
    endaction
  endseq
  );

  Stmt access_errors = (
    seq
      fn_send_read(`base + 'h0);
      fn_fail_on_apb_error(1);

      fn_send_write(`base + 'h0,'hffff,'1);
      fn_fail_on_apb_error(2);

      fn_send_write(`base + 'h0,'hffff,'b1);
      fn_fail_on_apb_error(3);

      fn_send_read(`base + 'h2);
      fn_pass_on_apb_error(4);

      fn_send_write(`base + 'h2,'hffff,'1);
      fn_pass_on_apb_error(5);

      fn_send_write(`base + 'h2,'hffff,'b1);
      fn_pass_on_apb_error(6);

      fn_send_read(`base + 'h4000);
      fn_fail_on_apb_error(7);

      fn_send_read(`base + 'h4004);
      fn_fail_on_apb_error(8);

    endseq
  );
  mkAutoFSM (seq
	  gen_msip;
	  $display("TEST1 PASSED >>>>>>>>>>>>>>>>>>>>>");
	  access_errors;
	  $display("TEST2 PASSED >>>>>>>>>>>>>>>>>>>>>");
		$finish (0);
	endseq);

endmodule:mkTb
endpackage:tb_clint

