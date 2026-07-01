// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Tuesday 21 April 2020 09:22:34 AM IST

Device configuration bus

*/
package dcbus_example ;

`ifdef async_reset
  import RegOverrides  :: *;
`endif
import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
`include "Logger.bsv"
import DCBus        :: * ;
import apb :: * ;
import Semi_FIFOF :: * ;
import ConfigReg  :: * ;
import StmtFSM      :: * ;
import DReg         :: * ;
import Connectable  :: * ;
import Clocks       :: * ;

typedef 4 TCfgReg;

`define base_addr 'h3000

/*module [Module] mkmodule (IWithDCBus#(DCBus#(aw, dw),Empty))
  provisos(
    Add#(6, _a, aw),         // address width greater than 6
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

    Add#(b__, 2, aw),
    Add#(a__, 3, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw)
    
  );

  Reg#(Bit#(8))  a <- mkReg('hAA) ; 
  ConfigReg#(Bit#(16)) b <- mkConfigReg('hBBAA) ; 
  Reg#(Bit#(32)) c <- mkReg('hDDCCBBAA) ; 
  Reg#(Bit#(64)) d <- mkReg('hDDCCBBAA55332211) ; 

  //Reg#(Bit#(32)) dcc_c = writeSideEffect(c, d._write('hdeadbeef));

  rule rl_upd_d;
   // b<= b + 1;
  endrule

  interface dcbus = interface DCBus
  method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size);
    Bit#(TLog#(TCfgReg)) index = truncate(addr >> 3);
    Tuple2#(Bool, Bit#(dw))  temp;
    case (index)
      0:  temp = fn_adjust_read(addr, size, a, Sz1, 3'b111);
      1:  temp = fn_adjust_read(addr, size, b, Sz1, 3'b111);
      2:  temp = fn_adjust_read(addr, size, c, Sz1, 3'b111);
      3:  temp = fn_adjust_read(addr, size, d, Sz8, 3'b000);
      default: temp = tuple2(False,0);
    endcase
    return temp; 
  endmethod
  method ActionValue#(Bool) write (Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strb);
    Bit#(TLog#(TCfgReg)) index = truncate(addr >> 3);
    case (index)
      0: begin let {succ, temp} <- fn_adjust_write(addr, data, strb, a, Sz1, 3'b111); if(succ) a<=temp; return succ; end
      1: begin let {succ, temp} <- fn_adjust_write(addr, data, strb, b, Sz2, 3'b111); if(succ) b<=temp; return succ; end
      2: begin let {succ, temp} <- fn_adjust_write(addr, data, strb, c, Sz4, 3'b111); if(succ) c<=temp; return succ; end
      3: begin let {succ, temp} <- fn_adjust_write(addr, data, strb, d, Sz8, 3'b000); if(succ) d<=temp; return succ; end
      default: return False;
    endcase
  endmethod
  endinterface;

endmodule:mkmodule*/

typedef DCRAddr#(48) ADRA;

module [ModWithDCBus#(aw,dw)] mkmodule (Empty)
  provisos(
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

    Add#(b__, 2, aw),
    Add#(a__, 3, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8)
  );

  Reg#(Bit#(8)) a <- mkDCBRegRW(ADRA{addr:'h0 , min:Sz1, max:Sz8, mask:3'b000}, 'hAA);
  Reg#(Bit#(16)) b <- mkDCBRegRW(ADRA{addr:'h9 ,  min:Sz1, max:Sz8, mask:3'b001}, 'hBBAA);
  Reg#(Bit#(32)) c <- mkDCBRegRWSe(ADRA{addr:'h10,  min:Sz1, max:Sz8, mask:3'b111}, 'hDDCCBBAA, a._write('hFF));
  Reg#(Bit#(64)) d <- mkDCBRegRW(ADRA{addr:'h18,  min:Sz1, max:Sz8, mask:3'b111}, 'hDDCCBBAA55332211);

  rule upd_d;
   // b <= b + 1;
  endrule

endmodule:mkmodule
module [Module] mkTb(Empty);

  let clk <- exposeCurrentClock;
  let rst <- exposeCurrentReset;

  ClockDividerIfc newclk <- mkClockDivider(4);
  Reset newrst <- mkAsyncReset(3, rst, newclk.slowClock);

  Ifc_device_apb#(16,32,0) mod <- mkdevice_apb(newclk.slowClock, newrst);
  /*doc:reg: */
  Reg#(Bit#(32)) rg_count <- mkReg('h00);
  Reg#(int) iter <- mkRegU;

  Ifc_apb_master_xactor#(16,32,0) master <- mkapb_master_xactor;

  mkConnection(master.apb_side,mod.slave);

  Stmt requests = (
    par
      seq
        master.fifo_side.i_request.enq(APB_request{ paddr:  `base_addr+'h9, pwrite : False,  pwdata : 'hdeadbeef, pstrb  : '1});
        master.fifo_side.i_request.enq(APB_request{ paddr:  `base_addr+'h10, pwrite : True,  pwdata : 'hdeadbeef, pstrb  : '1});
        master.fifo_side.i_request.enq(APB_request{ paddr:  `base_addr+'h0, pwrite : False,  pwdata : 'hdeadbeef, pstrb  : '1});
        delay(200);
      endseq
      seq
        for(iter <= 1; iter <= 3; iter <= iter + 1)
          action
            await (master.fifo_side.o_response.notEmpty);
            let resp = master.fifo_side.o_response.first;
            master.fifo_side.o_response.deq;
            $display("[%10d]\t Revieved Resp:",$time,fshow_apb_resp(resp));            
          endaction

      endseq
    endpar
  );

  FSM test <- mkFSM(requests);

  /*doc:rule: */
  rule rl_initiate(rg_count == 0);
    rg_count <= rg_count + 1;
    test.start;
  endrule:rl_initiate

  /*doc:rule: */
  rule rl_terminate (rg_count != 0 && test.done);
    $finish(0);
  endrule
endmodule:mkTb

typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Empty) Ifc_device_apb#(type aw, type dw, type uw);

module [Module] mkdevice_block(IWithDCBus#(DCBus#(aw,dw), Empty))
  provisos(
    Add#(6, _a, aw),         // address width greater than 6
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

    Add#(b__, 2, aw),
    Add#(a__, 3, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8)
  );
  let ifc <- exposeDCBusIFC(mkmodule);
  return ifc;
endmodule


module [Module] mkdevice_apb#(Clock device_clk, Reset device_rst)(Ifc_device_apb#(aw,dw,uw))
  provisos(
    Add#(6, _a, aw),         // address width greater than 6
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(b__, 2, aw),
    Add#(a__, 3, aw),
    Add#(dw, c__, 64),
    Add#(d__, TDiv#(dw, 8), 8)
  );
  let device = mkdevice_block(clocked_by device_clk, reset_by device_rst);
  Ifc_device_apb#(aw,dw,uw) uart <- dc2apb(device, `base_addr, device_clk, device_rst);
  return uart;
endmodule

/*(*synthesize*)
module mkdummy2(Ifc_device_apb#(16, 32, 0));
  let clk <- exposeCurrentClock;
  let rst <- exposeCurrentReset;
  let ifc();
  mkdevice_apb#(clk,rst) _temp(ifc);
  return ifc;
endmodule:mkdummy2*/

endpackage: dcbus_example

