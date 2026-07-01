// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Saturday 25 April 2020 07:16:12 PM IST

*/
package tb_plic ;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;
  import plic         :: * ;
  import DCBus        :: * ;
import  StmtFSM      :: *;
  `include "Logger.bsv"
`define nsources 16
`define ntargets 2
`define maxpriority 7
`define datasize 32

/*(*synthesize*)
module [Module] mkinst_plicapb(Ifc_plic_apb#(32, `datasize, 0, `nsources, `ntargets, `maxpriority));
  let clk <- exposeCurrentClock;
  let rst <- exposeCurrentReset;
  let ifc();
  mkplic_apb#(clk, rst) _temp(ifc);
  return ifc;
endmodule:mkinst_plicapb*/

module [Module] mkTb(Empty);
  IWithDCBus#(DCBus#(32,`datasize),Ifc_plic#(`nsources, `ntargets, `maxpriority)) mod <- mkplic;
  /*doc:reg: */
  Reg#(Bit#(32)) rg_count <- mkReg(0);
  Reg#(int) iter <- mkRegU;
  Vector #(`nsources, Reg #(Bool)) vrg_irqs <- replicateM (mkReg (False));
  // Drive all interrupt requests from local regs
  rule rl_drive_irq;
	  mod.device.sb_frm_gateway(pack(readVReg(vrg_irqs)));
  endrule:rl_drive_irq

    function Action fstmt_read_source_priority (Integer src, AccessSize sz);
    action
	  	$display("Reading to Address:%h",src*4);
	  	let {resp, data} <- mod.dcbus.read (fromInteger(src * 4), sz, PvU);
	  	if (!resp) begin $display("FAIL: Read to %h Unsuccessful",src*4); end
      $display("Read Data:%h",data);
    endaction
  endfunction

    function Action fstmt_set_source_priority (Integer src, Bit#(TLog#(`maxpriority)) prio,
                                              Bit#(TDiv#(`datasize,8)) strb);
    action
//	  	$display("Writing to Address:%h",src*4);
	  	let resp <- mod.dcbus.write (fromInteger(src * 4), zeroExtend (prio), strb, PvU);
	  	if (!resp) begin $display("FAIL: Write to %h Unsuccessful",src*4); $finish(0); end
	  endaction
  endfunction
  function Action fstmt_set_target_ies (Integer target, Bit #(32) ies);
  action
//	  $display("Writing to Address:%h",'h2000 + (target * 'h80));
	  let resp <- mod.dcbus.write ('h2000 + fromInteger(target * 'h80), zeroExtend (ies), '1, PvU);
	  if (!resp) begin $display("FAIL: Write to %h Unsuccessful",'h2000 + (target * 'h80)); $finish(0); end
	endaction
  endfunction
  function Action fstmt_set_target_threshold (Integer target, Bit#(TLog#(`maxpriority)) threshold);
  action
//	  $display("Writing to Address:%h",'h20_0000 + (target * 'h1000));
		let resp <- mod.dcbus.write('h20_0000 + fromInteger(target * 'h1000), zeroExtend (threshold), '1, PvU);
	  if (!resp) begin $display("FAIL: Write to %h Unsuccessful",'h20_0000 + (target * 'h1000)); $finish(0); end
	endaction
  endfunction
  function Action fstmt_claim (Integer target);
	  action
//	    $display("Reading from Address:%h",'h20_0004 + fromInteger(target * 'h1000));
      let {succ,temp} <- mod.dcbus.read('h20_0004 + fromInteger(target * 'h1000), dw2size(`datasize), PvU);
  	  if (!succ) begin $display("FAIL: Read to %h Unsuccessful",'h20_0004 + fromInteger(target * 'h1000)); $finish(0); end
	    $display ("fstmt_claim: PLIC returned %0d", temp);
	  endaction
  endfunction

  function Action fstmt_complete (Integer target, Bit#(TLog#(`nsources)) source_id);
	  action
//	    $display("Writing to Address:%h",'h20_0004 + fromInteger(target * 'h1000));
      let resp <- mod.dcbus.write('h20_0004 + fromInteger(target * 'h1000), zeroExtend(source_id),'1, PvU);
  	  if (!resp) begin $display("FAIL: Read to %h Unsuccessful",'h20_0004 ); $finish(0); end
	  endaction
  endfunction
   function Action fa_print_plic_eips ();
      action
	 $write ("PLIC.v_target  eip =");
	 $write (" ", fshow (mod.device.sb_to_targets[0]));
	 $write (" ", fshow (mod.device.sb_to_targets [1]));
	 $display ("");
      endaction
   endfunction

  Stmt init = (
    seq
		  $display ("Initializing PLIC");
		  fstmt_set_source_priority (1,  0, '1);
		  fstmt_set_source_priority (2,  0, '1);
		  fstmt_set_source_priority (3,  0, '1);
		  fstmt_set_source_priority (4,  0, '1);

		  fstmt_set_source_priority (5,  0, '1);
		  fstmt_set_source_priority (6,  0, '1);
		  fstmt_set_source_priority (7,  0, '1);
		  fstmt_set_source_priority (8,  0, '1);

		  fstmt_set_source_priority (9,  0, '1);
		  fstmt_set_source_priority (10, 0, '1);
		  fstmt_set_source_priority (11, 0, '1);
		  fstmt_set_source_priority (12, 0, '1);

		  fstmt_set_source_priority (13, 0, '1);
		  fstmt_set_source_priority (14, 0, '1);
		  fstmt_set_source_priority (15, 0, '1);
		  fstmt_set_source_priority (16, 0, '1);

		  fstmt_set_target_ies (0, 0);
		  fstmt_set_target_ies (1, 0);

		  fstmt_set_target_threshold (0, 7);
		  fstmt_set_target_threshold (1, 7);
		  delay (5);
		  $display ("Finished Initializing PLIC");
  	endseq
  );
  Stmt test3 = seq
		$display (">---------------- TEST 1");
		fstmt_read_source_priority(5, Sz1);
		fstmt_read_source_priority(2, Sz8);
	endseq;
  Stmt test1 = seq
		$display (">---------------- TEST 1");
		fstmt_set_source_priority (5, 4, 1);
		fstmt_set_source_priority (2, 4, 1);
		fa_print_plic_eips;

		fstmt_set_target_ies (0, 'b10_0100);    // bit 5 and bit 2
		fa_print_plic_eips;
		fstmt_set_target_threshold (0, 4);
		fa_print_plic_eips;

		fstmt_set_target_ies (1, 'b10_0100);    // bit 5
		fa_print_plic_eips;
		fstmt_set_target_threshold (1, 2);
		fa_print_plic_eips;

		mod.device.show_PLIC_state;
		fa_print_plic_eips;
    action
  		vrg_irqs [4] <= True;
  		vrg_irqs [1] <= True;
  	endaction
		delay (2);
		mod.device.show_PLIC_state;
		fa_print_plic_eips;

		fstmt_set_target_threshold (0, 3);
		mod.device.show_PLIC_state;
		fa_print_plic_eips;

		fstmt_claim (1);
		mod.device.show_PLIC_state;
		fa_print_plic_eips;
    action
  		vrg_irqs [4] <= False;
  		vrg_irqs [1] <= False;
  	endaction

		fstmt_complete (1, 5);
		mod.device.show_PLIC_state;
		mod.device.show_PLIC_state;
		fa_print_plic_eips;
	endseq;
  Stmt test2 = seq
		$display (">---------------- TEST 2");
		fstmt_set_source_priority (2, 4, '1);
		fstmt_set_source_priority (5, 6, '1);
		fa_print_plic_eips;

		fstmt_set_target_ies (0, 'b10_0100);    // bit 5 and bit 2
		fa_print_plic_eips;
		fstmt_set_target_threshold (0, 7);
		fa_print_plic_eips;

		fstmt_set_target_ies (1, 'b10_0100);    // bit 5
		fa_print_plic_eips;
		fstmt_set_target_threshold (1, 4);
		fa_print_plic_eips;

		mod.device.show_PLIC_state;
		fa_print_plic_eips;
    action
  		vrg_irqs [4] <= True;
  		vrg_irqs [1] <= True;
  	endaction
		delay (2);
		mod.device.show_PLIC_state;
		fa_print_plic_eips;

		fstmt_set_target_threshold (0, 3);
		mod.device.show_PLIC_state;
		fa_print_plic_eips;

		fstmt_claim (1);
		mod.device.show_PLIC_state;
		fa_print_plic_eips;
    action
  		vrg_irqs [4] <= False;
  		vrg_irqs [1] <= False;
  	endaction

		fstmt_complete (1, 5);
		mod.device.show_PLIC_state;
		fa_print_plic_eips;
	endseq;
   mkAutoFSM (seq
		 init;
		// test3;
     test1;
     test2;
		 $finish (0);
	 endseq);
endmodule:mkTb
endpackage: tb_plic

