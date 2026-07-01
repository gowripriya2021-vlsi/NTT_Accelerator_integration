// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details 
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 22 April 2020 04:33:43 PM IST

*/
package clint;

	import ConfigReg::*;
	import ConcatReg :: * ;
	import axi4l::*;
	import axi4::*;
  import apb::*;
  import DCBus::*;
	import BUtils ::*;
  import GetPut::*;
  import Assert::*;
  import DefaultValue::*;
  import Reserved :: * ;
  
  export Ifc_clint_axi4l    (..);
  export Ifc_clint_apb      (..);
  export Ifc_clint_sb       (..);
  export mkclint_axi4l;
  export mkclint_apb;
  export mk_clint_block;

  typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw), Ifc_clint_sb#(tick_count, msip_size))
      Ifc_clint_axi4l#(type aw, type dw, type uw, numeric type tick_count, numeric type msip_size);
  typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Ifc_clint_sb#(tick_count, msip_size))
      Ifc_clint_apb#(type aw, type dw, type uw, numeric type tick_count, numeric type msip_size);
  /*typedef IWithSlave#(Ifc_axi4_slave#(iw, aw, dw, uw), Ifc_clint_sb#(tick_count, msip_size))
      Ifc_clint_axi4#(type iw, type aw, type dw, type uw, numeric type tick_count, numeric type msip_size);*/

  typedef struct{
    ReservedZero#(TSub#(64,m)) zeros;
    Bit#(m) msip;
  } MsipReg#(numeric type m) deriving (Bits, Eq, FShow);

  interface Ifc_clint_sb#(numeric type tick_count, numeric type msip_size);
    (*always_ready*)
    method Bit#(msip_size) sb_clint_msip;
    (*always_ready*)
    method Bit#(1) sb_clint_mtip;
    (*always_ready*)
    method Bit#(64) sb_clint_mtime;
	endinterface

  module [ModWithDCBus#(aw,dw)] mk_clint#(parameter Bit#(64) timecmp_reset_val)(Ifc_clint_sb#( tick_count, msip_size))
		provisos(
		  Log#(tick_count, tick_count_bits),
      Add#(16, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      Add#(d__, 3, aw),

      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(b__, TDiv#(dw, 8), 8),
      Mul#(TDiv#(TAdd#(TSub#(64, msip_size), msip_size), 8), 8, TAdd#(TSub#(64,
    msip_size), msip_size))

		);	

    staticAssert(valueOf(TExp#(tick_count_bits))==valueOf(tick_count),"tick count not a power of 2");

    DCRAddr#(aw,3) attr_msip     = DCRAddr{addr:'h0000, min: Sz1, max:Sz8, mask:3'b100}; 
    DCRAddr#(aw,3) attr_mtimecmp = DCRAddr{addr:'h4000, min: Sz1, max:Sz8, mask:3'b111};
    DCRAddr#(aw,3) attr_mtime    = DCRAddr{addr:'hbff8, min: Sz1, max:Sz8, mask:3'b111};
    
		Reg#(Bit#(1))               rg_mtip          <- mkReg(0);
		Reg#(Bit#(tick_count_bits)) rg_tick          <- mkReg(0);

		Reg#(MsipReg#(msip_size)) rg_msip     <- mkDCBRegRW(attr_msip, unpack(0));
		Reg#(Bit#(64))            rg_mtimecmp <- mkDCBRegRWSe(attr_mtimecmp,  timecmp_reset_val, rg_mtip._write(0));
    Reg#(Bit#(64))            rg_mtime    <- mkDCBRegRW(attr_mtime, 'h0);


		rule rl_generate_interrupt;
			rg_mtip<=pack(rg_mtime >= rg_mtimecmp);
		endrule:rl_generate_interrupt

		rule rl_increment_timer;
			if(rg_tick == 0)begin
				rg_mtime <= rg_mtime + 1;
			end
			rg_tick <= rg_tick + 1;
		endrule:rl_increment_timer

    method sb_clint_msip  = rg_msip.msip;
    method sb_clint_mtip  = rg_mtip;
    method sb_clint_mtime = rg_mtime;
  endmodule:mk_clint

  module [Module] mk_clint_block#(parameter Bit#(64) timecmp_reset_val)
    (IWithDCBus#(DCBus#(aw,dw), Ifc_clint_sb#(tick_count, msip_size)))
		provisos(
		  Log#(tick_count, tick_count_bits),
      Add#(16, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      Add#(d__, 3, aw),

      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(b__, TDiv#(dw, 8), 8),
      Mul#(TDiv#(TAdd#(TSub#(64, msip_size), msip_size), 8), 8, TAdd#(TSub#(64,
    msip_size), msip_size))
		);	
    let ifc <- exposeDCBusIFC(mk_clint(timecmp_reset_val));
    return ifc;
  endmodule:mk_clint_block

  module [Module] mkclint_axi4l#(parameter Bit#(64) timecmp_reset_val, parameter Integer base, Clock clint_clk, Reset clint_rst)
    (Ifc_clint_axi4l#(aw, dw, uw, tick_count, msip_size))
		provisos(
		  Log#(tick_count, tick_count_bits),
      Add#(16, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      Add#(d__, 3, aw),

      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(b__, TDiv#(dw, 8), 8),
      Mul#(TDiv#(TAdd#(TSub#(64, msip_size), msip_size), 8), 8, TAdd#(TSub#(64,
    msip_size), msip_size))
		);	

    let clint_mod = mk_clint_block(timecmp_reset_val, clocked_by clint_clk, reset_by clint_rst);
    Ifc_clint_axi4l#(aw, dw, uw, tick_count, msip_size) clint <-
        dc2axi4l(clint_mod, base, clint_clk, clint_rst);
    return clint;
  endmodule:mkclint_axi4l

  module [Module] mkclint_apb#(parameter Bit#(64) timecmp_reset_val, parameter Integer base, Clock clint_clk, Reset clint_rst)
  (Ifc_clint_apb#(aw, dw, uw, tick_count, msip_size))
		provisos(
		  Log#(tick_count, tick_count_bits),
      Add#(16, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      Add#(d__, 3, aw),

      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(b__, TDiv#(dw, 8), 8),
      Mul#(TDiv#(TAdd#(TSub#(64, msip_size), msip_size), 8), 8, TAdd#(TSub#(64,
    msip_size), msip_size))
		);	
    
    let clint_mod = mk_clint_block(timecmp_reset_val, clocked_by clint_clk, reset_by clint_rst);
    Ifc_clint_apb#(aw, dw, uw, tick_count, msip_size) clint <-
        dc2apb(clint_mod, base, clint_clk, clint_rst);
    return clint;
  endmodule:mkclint_apb


  /*module [Module] mkclint_axi4#(Clock clint_clk, Reset clint_rst)
  (Ifc_clint_axi4#(iw, aw, dw, uw, tick_count, msip_size))
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
    
    let clint_mod = mk_clint_block(clocked_by clint_clk, reset_by clint_rst);
    Ifc_clint_axi4#(iw, aw, dw, uw, tick_count, msip_size) clint <-
        dc2axi4(clint_mod, clint_clk, clint_rst);
    return clint;
  endmodule:mkclint_axi4*/


endpackage:clint





