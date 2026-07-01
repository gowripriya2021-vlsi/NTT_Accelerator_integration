package DCBusCounter;

`ifdef async_reset
  import RegOverrides  :: *;
`endif
import DCBus        :: * ;
import apb          :: * ;
import FIFOF        :: * ;
import Semi_FIFOF   :: * ;
import Vector       :: * ;
import ConfigReg    :: * ;
import DReg         :: * ;
import Connectable  :: * ;
import Clocks       :: * ;
import StmtFSM      :: * ;

`include "Logger.bsv"

typedef 16 DCBADDRWIDTH; // address bus to decode
typedef 32 DCBDATAWIDTH; //size of configuration data bus
typedef 8 COUNTERSIZE;

`define base_addr 'h2000
`define initialvalue 5

typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Counter#(size_t)) Ifc_counter_apb#(type aw, type dw, type uw, numeric type size_t);

interface Counter#(numeric type size_t);
   method Bool   isZero();
   method Action decrement();
   method Action load(); // load via config register
endinterface

/* This module exposes the collected interfaces */
module [Module] mkCounter_block(IWithDCBus#(DCBus#(aw,dw), Counter#(size_t)))provisos(
      Add#(8, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(1, a__, TLog#(TDiv#(dw, 8))),
      Add#(b__, 1, aw),
      Add#(TExp#(TLog#(size_t)),0,size_t),
      Add#(d__, TDiv#(dw, 8), 8),
      Add#(size_t, e__, 64),
      Add#(size_t, f__, dw),
      Mul#(TDiv#(size_t, 8), 8, size_t)
  );
   let ifc <- exposeDCBusIFC(mkCounter);
   return (ifc);
endmodule:mkCounter_block

module [Module] mkcounter_apb#(Clock counter_clk, Reset counter_rst)(Ifc_counter_apb#(aw,dw,uw,size_t))
   provisos(
      Add#(8, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(TExp#(TLog#(size_t)),0,size_t),
      Add#(1, a__, TLog#(TDiv#(dw, 8))),
      Add#(b__, 1, aw),
      Add#(d__, TDiv#(dw, 8), 8),
      Add#(size_t, e__, 64),
      Add#(size_t, f__, dw),
      Mul#(TDiv#(size_t, 8), 8, size_t)
  );
  let device = mkCounter_block(clocked_by counter_clk, reset_by counter_rst);
  Ifc_counter_apb#(aw,dw,uw,size_t) counter <- dc2apb(device, `base_addr, counter_clk, counter_rst);
  return counter;
endmodule:mkcounter_apb

/*
   This module is interfaced as slave to APB using Device Configuration Bus.
   The 'counter' Register is controlled via the DCBus' Reg interface
   that is used to load the counter.
*/
module [ModWithDCBus#(aw,dw)] mkCounter(Counter#(size_t))
   provisos(
      Add#(8, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(TExp#(TLog#(size_t)),0,size_t),
      Add#(size_t,_d,dw),
      Add#(1, a__, TLog#(TDiv#(dw, 8))),
      Add#(b__, 1, aw),
      Add#(d__, TDiv#(dw, 8), 8),
      Add#(size_t, e__, 64),
      Add#(size_t, f__, dw),
      Mul#(TDiv#(size_t, 8), 8, size_t)
   );
   // configuration register with write in Machine mode and read in any mode
   DCRAddr#(aw,1) counter_reg = DCRAddr {addr: 13, min: Sz1, max: Sz4, mask: 1'b1, wr_perm: PvM};
   Reg#(Bit#(size_t)) counter <- mkDCBRegRW(counter_reg, 'h0);

   Reg#(Bit#(size_t)) pvt_reg <- mkReg(0);
   method Bool isZero();
      return (pvt_reg == 0);
   endmethod

   method Action decrement();
      pvt_reg <= pvt_reg - 1;
      counter <= pvt_reg;
   endmethod

   method Action load();
      pvt_reg <= counter;
   endmethod

endmodule:mkCounter

/*
Testbench that tests the counter connected as APB peripheral and uses the
DCBus Configuration register to be loaded nd
*/
(* synthesize *)
module mkDCBusTb(Empty);

   let clk <- exposeCurrentClock;
   let rst <- exposeCurrentReset;
   Reg#(Bit#(32)) rg_count <- mkReg(`initialvalue);
   Reg#(Bool) init <- mkReg(False);

   Ifc_counter_apb#(DCBADDRWIDTH,DCBDATAWIDTH,0,COUNTERSIZE) the_counter <- mkcounter_apb(clk, rst);
   Ifc_apb_master_xactor#(DCBADDRWIDTH,DCBDATAWIDTH,0) master <- mkapb_master_xactor;

   mkConnection(master.apb_side,the_counter.slave);

   rule display_value (master.fifo_side.o_response.notEmpty && init == True);
      let read_value = master.fifo_side.o_response.first;
      master.fifo_side.o_response.deq;
      `logLevel( mkDCBusTb, 1, $format("DCBUSCOUNTER: Recieved Resp:",fshow_apb_resp(read_value)))
      if(rg_count == 0)
         $finish();
   endrule

   rule init_counter (the_counter.device.isZero() && init == False);
      rg_count <= `initialvalue;
      master.fifo_side.i_request.enq(APB_request{ paddr: `base_addr+13, pwrite : True, pwdata : `initialvalue, prot: 3'b001, pstrb  : '1});
      `logLevel( mkDCBusTb, 1, $format("DCBUSCOUNTER: Initializing Counter with Initial value of %2d",rg_count))
      init <= True;
   endrule

   rule load_counter (the_counter.device.isZero() && init == True);
      if(rg_count != 0)
         the_counter.device.load();
   endrule

   // A rule that decrements and reads the device register
   rule decrement (!the_counter.device.isZero());
      rg_count <=  rg_count-1;
      the_counter.device.decrement();
      master.fifo_side.i_request.enq(APB_request {paddr: `base_addr+13, pwdata: ?, pwrite: False, prot: 3'b010, pstrb:'1});
   endrule

endmodule:mkDCBusTb

endpackage:DCBusCounter
