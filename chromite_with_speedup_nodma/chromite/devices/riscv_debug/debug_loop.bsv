// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details 

/*
--------------------------------------------------------------------------------------------------
Author: Neel Gala
Email id: neelgala@gmail.com
Details: This module holds the self loop for halt state
--------------------------------------------------------------------------------------------------
*/
package debug_loop;

import Vector       :: * ;
import FIFOF        :: * ;
import DReg         :: * ;
import SpecialFIFOs :: * ;
import BRAMCore     :: * ;
import FIFO         :: * ;

import axi4         :: * ;
import axi4l        :: * ;
import apb          :: * ;
import Semi_FIFOF   :: * ;
import BUtils       :: * ;
import DCBus        :: * ;
  
typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw), Empty) Ifc_debug_loop_axi4l#(type aw, type dw, type uw);
typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Empty)   Ifc_debug_loop_apb#(type aw, type dw, type uw);

module [ModWithDCBus#(aw,dw)] mkdebug_loop(Empty)
	provisos(
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(b__, TDiv#(dw, 8), 8)
	);	
  
  DCRAddr#(aw,2) attr_i1 = DCRAddr{addr:'h00, min: Sz1, max:Sz4, mask:2'b11}; 
  DCRAddr#(aw,2) attr_i2 = DCRAddr{addr:'h04, min: Sz1, max:Sz4, mask:2'b11};
  DCRAddr#(aw,2) attr_i3 = DCRAddr{addr:'h08, min: Sz1, max:Sz4, mask:2'b11};
  DCRAddr#(aw,2) attr_i4 = DCRAddr{addr:'h0c, min: Sz1, max:Sz4, mask:2'b11};
  
  Reg#(Bit#(32)) rg_inst1 <- mkDCBRegRO(attr_i1, 'h0000100f); 
  Reg#(Bit#(32)) rg_inst2 <- mkDCBRegRO(attr_i2, 'h00000013); 
  Reg#(Bit#(32)) rg_inst3 <- mkDCBRegRO(attr_i3, 'hffdff06f); 
  Reg#(Bit#(32)) rg_inst4 <- mkDCBRegRO(attr_i4, 'h0000006f); 
  
endmodule:mkdebug_loop

module [Module] mk_debug_loop_block
  (IWithDCBus#(DCBus#(aw,dw), Empty))
	provisos(
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(b__, TDiv#(dw, 8), 8)
	);	
  let ifc <- exposeDCBusIFC(mkdebug_loop);
  return ifc;
endmodule:mk_debug_loop_block

module [Module] mkdebug_loop_axi4l#(parameter Integer base, Clock debug_loop_clk, Reset debug_loop_rst)
  (Ifc_debug_loop_axi4l#(aw, dw, uw))
	provisos(
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(b__, TDiv#(dw, 8), 8)
	);	

  let debug_loop_mod = mk_debug_loop_block(clocked_by debug_loop_clk, reset_by debug_loop_rst);
  Ifc_debug_loop_axi4l#(aw, dw, uw) debug_loop <-
      dc2axi4l(debug_loop_mod, base, debug_loop_clk, debug_loop_rst);
  return debug_loop;
endmodule:mkdebug_loop_axi4l

module [Module] mkdebug_loop_apb#(parameter Integer base, Clock debug_loop_clk, Reset debug_loop_rst)
  (Ifc_debug_loop_apb#(aw, dw, uw))
	provisos(
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(b__, TDiv#(dw, 8), 8)
	);	
  
  let debug_loop_mod = mk_debug_loop_block(clocked_by debug_loop_clk, reset_by debug_loop_rst);
  Ifc_debug_loop_apb#(aw, dw, uw) debug_loop <-
      dc2apb(debug_loop_mod, base, debug_loop_clk, debug_loop_rst);
  return debug_loop;
endmodule:mkdebug_loop_apb


  /*module [Module] mkdebug_loop_axi4#(Clock debug_loop_clk, Reset debug_loop_rst)
  (Ifc_debug_loop_axi4#(iw, aw, dw, uw, tick_count, msip_size))
		provisos(
		  Log#(tick_count, tick_count_bits),
      Add#(16, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(b__, TDiv#(dw, 8), 8),
      Mul#(TDiv#(TAdd#(TSub#(64, msip_size), msip_size), 8), 8, TAdd#(TSub#(64,
    msip_size), msip_size))

		);	
    
    let debug_loop_mod = mk_debug_loop_block(clocked_by debug_loop_clk, reset_by debug_loop_rst);
    Ifc_debug_loop_axi4#(iw, aw, dw, uw, tick_count, msip_size) debug_loop <-
        dc2axi4(debug_loop_mod, debug_loop_clk, debug_loop_rst);
    return debug_loop;
  endmodule:mkdebug_loop_axi4*/

endpackage:debug_loop

