// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms

package aclint;

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
  
export Ifc_aclint_axi4l    (..);
export Ifc_aclint_apb      (..);
export Ifc_aclint_sb       (..);
export mkaclint_axi4l;
export mkaclint_apb;
export mkaclint_block;

typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Ifc_aclint_sb#(tick_count, msip_size, num_timecmp, num_sswi))
      Ifc_aclint_apb#(type aw, type dw, type uw, numeric type tick_count, numeric type msip_size, numeric type num_timecmp, numeric type num_sswi);
      
typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw), Ifc_aclint_sb#(tick_count, msip_size, num_timecmp, num_sswi))
      Ifc_aclint_axi4l#(type aw, type dw, type uw, numeric type tick_count, numeric type msip_size, numeric type num_timecmp, numeric type num_sswi);

/*typedef IWithSlave#(Ifc_axi4_slave#(iw, aw, dw, uw), Ifc_aclint_sb#(tick_count, msip_size, num_timecmp, num_sswi))
      Ifc_aclint_axi4#(type iw, type aw, type dw, type uw, numeric type tick_count, numeric type msip_size, numeric type num_timecmp,numeric type num_sswi);*/

typedef struct{
    ReservedZero#(TSub#(32,m)) zeros;
   Bit#(m) msip;
  } MsipReg#(numeric type m) deriving (Bits, Eq, FShow);

typedef struct{
    ReservedZero#(TSub#(32,m)) zeros;
   Bit#(m) setssip;
  } SetssipReg#(numeric type m) deriving (Bits, Eq, FShow);
  
interface Ifc_aclint_sb#(numeric type tick_count, numeric type msip_size, numeric type num_timecmp, numeric type num_sswi );
    (*always_ready*)
    method (Bit#(msip_size)) sb_aclint_msip;
    (*always_ready*)
    method Bit#(num_timecmp) sb_aclint_mtip;
    (*always_ready*)
    method Bit#(64) sb_aclint_mtime;
    (*always_ready*)
    method (Bit#(num_sswi)) sb_aclint_setssip;
endinterface

  
module [ModWithDCBus#(aw,dw)] mkaclint #(parameter Bit#(aw) msip_base, parameter Bit#(aw) mtimecmp_base, parameter Bit#(aw) mtime_base, parameter Bit#(aw) ssip_base)(Ifc_aclint_sb#( tick_count, msip_size, num_timecmp, num_sswi))
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
    	msip_size), msip_size)),
    	Mul#(TDiv#(TAdd#(TSub#(64, num_timecmp), num_timecmp), 8), 8, TAdd#(TSub#(64,
    	num_timecmp), num_timecmp))
		);	
		
staticAssert(valueOf(TExp#(tick_count_bits))==valueOf(tick_count),"tick count not a power of 2");

Integer numint = valueof(num_timecmp);
Integer msip_num = valueof(msip_size);
Integer setssip_num = valueof(num_sswi);
DCRAddr#(aw,3) attr_msip[msip_num];
for(Integer i=0;i<(msip_num);i=i+1)
	begin
	Bit#(aw) j= fromInteger(i);
	attr_msip[i]     = DCRAddr{addr:msip_base+j*'h0004, min: Sz1, max:Sz8, mask:3'b100}; 
	end
DCRAddr#(aw,3) attr_mtimecmp[numint];
for(Integer i=0;i<(numint);i=i+1)
	begin
	Bit#(aw) j= fromInteger(i);
 	attr_mtimecmp[i] = (DCRAddr{addr:(mtimecmp_base+j*'h0008), min: Sz1, max:Sz8, mask:3'b111}); 
    	end
    		
DCRAddr#(aw,3) attr_mtime    = DCRAddr{addr:mtime_base, min: Sz1, max:Sz8, mask:3'b111};

DCRAddr#(aw,3) attr_setssip[setssip_num];
for(Integer i=0;i<(setssip_num);i=i+1)
	begin
	Bit#(aw) j= fromInteger(i);
	attr_setssip[i]     = DCRAddr{addr:ssip_base+j*'h0004, min: Sz1, max:Sz8, mask:3'b100}; 
	end
    
Reg#(Bit#(1)) rg_mtip[numint];
for(Integer i=0;i<(numint);i=i+1)
	begin
	rg_mtip[i]          <- mkReg(0);
	end
		
Reg#(Bit#(tick_count_bits)) rg_tick          <- mkReg(0);

Reg#(MsipReg#(1))  rg_msip[msip_num];
for(Integer i=0;i<(msip_num);i=i+1)
	begin
	rg_msip[i]     <- mkDCBRegRW(attr_msip[i], unpack(0));
	end
	
Reg#(Bit#(64)) rg_mtimecmp[numint];	
for(Integer i=0;i<(numint);i=i+1)
	begin
	rg_mtimecmp[i] <- mkDCBRegRWSe(attr_mtimecmp[i],  '1, rg_mtip[i]._write(0));
	end
		
Reg#(Bit#(64))              rg_mtime    <- mkDCBRegRW(attr_mtime, 'h0);

Reg#(SetssipReg#(1))  rg_setssip[setssip_num];
for(Integer i=0;i<(setssip_num);i=i+1)
	begin
	rg_setssip[i]     <- mkDCBRegRW(attr_setssip[i], unpack(0));
	end

rule rl_generate_interrupt;
		
for(Integer i=0;i<(numint);i=i+1)
	begin
	rg_mtip[i]<=pack(rg_mtime >= rg_mtimecmp[i]); 
	end
endrule:rl_generate_interrupt

rule rl_increment_timer;
if(rg_tick == 0)begin
	rg_mtime <= rg_mtime + 1;
end
rg_tick <= rg_tick + 1;
endrule:rl_increment_timer
 
method sb_aclint_msip;
Bit#(msip_num) sb_aclint_msipx;
sb_aclint_msipx=0;
for(Integer i=0;i<(msip_num);i=i+1)
	begin
	sb_aclint_msipx[i]= rg_msip[i].msip;
	end
	return sb_aclint_msipx;
endmethod
  
method sb_aclint_mtip;
Bit#(num_timecmp) sb_aclint_mtipx;
sb_aclint_mtipx=0;
for(Integer i=0;i<(numint);i=i+1)
	begin
	sb_aclint_mtipx[i]= rg_mtip[i];
	end
	return sb_aclint_mtipx;
endmethod
method sb_aclint_mtime = rg_mtime;

method sb_aclint_setssip;
Bit#(setssip_num) sb_aclint_setssipx;
sb_aclint_setssipx=0;
for(Integer i=0;i<(setssip_num);i=i+1)
	begin
	if(rg_setssip[i].setssip==1)
	begin
	sb_aclint_setssipx[i]= 1;
	end
	else
	begin
	sb_aclint_setssipx[i]= 0;
	end
	end
	return sb_aclint_setssipx;
endmethod

endmodule:mkaclint
  
module [Module] mkaclint_block #(parameter Bit#(aw) msip_base, parameter Bit#(aw) mtimecmp_base, parameter Bit#(aw) mtime_base, parameter Bit#(aw) ssip_base)
    	(IWithDCBus#(DCBus#(aw,dw), Ifc_aclint_sb#(tick_count, msip_size, num_timecmp, num_sswi)))
	provisos(Log#(tick_count, tick_count_bits),
      	Add#(16, _a, aw),
      	Add#(8, _b, dw),         // data atleast 8 bits
      	Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      	Add#(d__, 3, aw),
	Add#(a__, 2, aw),
      	Add#(dw, c__, 64),
      	Add#(TExp#(TLog#(dw)),0,dw),
      	Add#(b__, TDiv#(dw, 8), 8),
      	Mul#(TDiv#(TAdd#(TSub#(64, msip_size), msip_size), 8), 8, TAdd#(TSub#(64,
    	msip_size), msip_size)),
    	Mul#(TDiv#(TAdd#(TSub#(64, num_timecmp), num_timecmp), 8), 8, TAdd#(TSub#(64,
    	num_timecmp), num_timecmp))
		);	
    let ifc <- exposeDCBusIFC(mkaclint(msip_base, mtimecmp_base, mtime_base,ssip_base ));
    return ifc;
endmodule:mkaclint_block

module [Module] mkaclint_apb#(parameter Integer base,parameter Bit#(aw) msip_base, parameter Bit#(aw) mtimecmp_base, parameter Bit#(aw) mtime_base, parameter Bit#(aw) ssip_base, Clock aclint_clk, Reset aclint_rst)
  (Ifc_aclint_apb#(aw, dw, uw, tick_count, msip_size, num_timecmp, num_sswi))
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
      msip_size), msip_size)),
      Mul#(TDiv#(TAdd#(TSub#(64, num_timecmp), num_timecmp), 8), 8, TAdd#(TSub#(64,
      num_timecmp), num_timecmp))
		);	
    
    let aclint_mod = mkaclint_block(msip_base, mtimecmp_base, mtime_base,ssip_base , clocked_by aclint_clk, reset_by aclint_rst);
    Ifc_aclint_apb#(aw, dw, uw, tick_count, msip_size, num_timecmp, num_sswi) aclint <-
        dc2apb(aclint_mod, base, aclint_clk, aclint_rst);
    return aclint;
endmodule:mkaclint_apb
  
  module [Module] mkaclint_axi4l#(parameter Integer base,parameter Bit#(aw) msip_base, parameter Bit#(aw) mtimecmp_base, parameter Bit#(aw) mtime_base, parameter Bit#(aw) ssip_base, Clock aclint_clk, Reset aclint_rst)
    (Ifc_aclint_axi4l#(aw, dw, uw, tick_count, msip_size, num_timecmp, num_sswi))
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
    msip_size), msip_size)),
    Mul#(TDiv#(TAdd#(TSub#(64, num_timecmp), num_timecmp), 8), 8, TAdd#(TSub#(64,
    	num_timecmp), num_timecmp))
		);	

    let aclint_mod = mkaclint_block(msip_base, mtimecmp_base, mtime_base,ssip_base , clocked_by aclint_clk, reset_by aclint_rst);
    Ifc_aclint_axi4l#(aw, dw, uw, tick_count, msip_size, num_timecmp, num_sswi) aclint <-
        dc2axi4l(aclint_mod, base, aclint_clk, aclint_rst);
    return aclint;
    endmodule:mkaclint_axi4l
    
 /*module [Module] mkaclint_axi4#(parameter Integer base,parameter Bit#(aw) msip_base, parameter Bit#(aw) mtimecmp_base, parameter Bit#(aw) mtime_base, parameter Bit#(aw) ssip_base,Clock aclint_clk, Reset aclint_rst)
  (Ifc_aclint_axi4#(iw, aw, dw, uw, tick_count, msip_size, num_sswi))
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
    
    let aclint_mod = mkaclint_block(msip_base, mtimecmp_base, mtime_base,ssip_base , clocked_by aclint_clk, reset_by aclint_rst);
    Ifc_aclint_axi4#(iw, aw, dw, uw, tick_count, msip_size, num_sswi) aclint <-
        dc2axi4(aclint_mod, aclint_clk, aclint_rst);
    return aclint;
  endmodule:mkaclint_axi4*/

  endpackage:aclint
