// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Friday 26 June 2020 03:31:46 PM

*/
package bootconfig ;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;

`include "Logger.bsv"
import apb          :: * ;
import axi4l        :: * ;
//import axi4          :: * ;
import DCBus        :: * ;
import Reserved :: *;


typedef DCRAddr#(7, 2) MMRA; // Memory mapped registre attributes
typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw), Ifc_bootconfig#(size))
    Ifc_bootconfig_axi4l#(type aw, type dw, type uw, numeric type size);
typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Ifc_bootconfig#(size))
    Ifc_bootconfig_apb#(type aw, type dw, type uw, numeric type size);

interface Ifc_bootconfig# (numeric type size);
  (*always_ready, always_enabled*)
  method Action io (Bit#(size) conf);
endinterface:Ifc_bootconfig

typedef struct{
  ReservedZero#(TSub#(32,size)) zeros;
  Bit#(size) configs;
} ConfigType#(numeric type size) deriving(Bits, Eq, FShow);

module [ModWithDCBus#(aw,dw)] mk_bootconfig (Ifc_bootconfig#(size))
  provisos(  
    Add#(16, _a, aw),
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8),
    Mul#(TDiv#(TAdd#(TSub#(32, size), size), 8), 8, TAdd#(TSub#(32, size),
    size))
  );
  
  DCRAddr#(aw,2) attr_config_Reg  = DCRAddr{addr:'h0 ,min:Sz1,max:Sz4,mask:2'b00};
  Reg#(ConfigType#(size))  rg_config   <- mkDCBRegRO(attr_config_Reg ,unpack(0));

  method Action io (Bit#(size) conf);
    rg_config.configs <= conf;
  endmethod:io

endmodule: mk_bootconfig

module [Module] mk_bootconfig_block(IWithDCBus#(DCBus#(aw,dw), Ifc_bootconfig#(size)))
	provisos(
    Add#(16, _a, aw),
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8),
    Mul#(TDiv#(TAdd#(TSub#(32, size), size), 8), 8, TAdd#(TSub#(32, size),
    size))

	);	
  let ifc <- exposeDCBusIFC(mk_bootconfig);
  return ifc;
endmodule:mk_bootconfig_block
module [Module] mkbootconfig_axi4l#(parameter Integer base, Clock bootconfig_clk, Reset bootconfig_rst)
  (Ifc_bootconfig_axi4l#(aw, dw, uw, size))
	provisos(
    Add#(16, _a, aw),
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8),
    Mul#(TDiv#(TAdd#(TSub#(32, size), size), 8), 8, TAdd#(TSub#(32, size),
    size))
	);	

  let bootconfig_mod = mk_bootconfig_block(clocked_by bootconfig_clk, reset_by bootconfig_rst);
  Ifc_bootconfig_axi4l#(aw, dw, uw, size) bootconfig <-
      dc2axi4l(bootconfig_mod, base, bootconfig_clk, bootconfig_rst);
  return bootconfig;
endmodule:mkbootconfig_axi4l

module [Module] mkbootconfig_apb#(parameter Integer base,Clock bootconfig_clk, Reset bootconfig_rst)
  (Ifc_bootconfig_apb#(aw, dw, uw, size))
	provisos(
    Add#(16, _a, aw),
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8),
    Mul#(TDiv#(TAdd#(TSub#(32, size), size), 8), 8, TAdd#(TSub#(32, size),
    size))
	);	

  let bootconfig_mod = mk_bootconfig_block(clocked_by bootconfig_clk, reset_by bootconfig_rst);
  Ifc_bootconfig_apb#(aw, dw, uw, size) bootconfig <-
      dc2apb(bootconfig_mod, base, bootconfig_clk, bootconfig_rst);
  return bootconfig;
endmodule:mkbootconfig_apb
/*module [Module] mkbootconfig_axi4#(Clock bootconfig_clk, Reset bootconfig_rst)
  (Ifc_bootconfig_axi4#(iw, aw, dw, uw, size))
	provisos(
    Add#(16, _a, aw),
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(dw, _c, 32), // not more than 32 bootconfigs per block

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8),
    Mul#(TDiv#(TAdd#(TSub#(32, size), size), 8), 8, TAdd#(TSub#(32, size),
    size))
	);	

  let bootconfig_mod = mk_bootconfig_block(clocked_by bootconfig_clk, reset_by bootconfig_rst);
  Ifc_bootconfig_axi4#(iw, aw, dw, uw, size) bootconfig <-
      dc2axi4(bootconfig_mod, bootconfig_clk, bootconfig_rst);
  return bootconfig;
endmodule:mkbootconfig_axi4*/
   
endpackage: bootconfig

