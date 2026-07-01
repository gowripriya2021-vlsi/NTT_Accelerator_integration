// see LICENSE.incore for more details on licensing terms
/*
Author: Arjun Menon, arjun@incoresemi.com
Description: This package consists of Wire implementations that can connect to CBus. The Bluespec
             library of CBus only provides Reg variants. Hence, whenever a register need not be
             instantiated for a config address, one of these modules can be used. Moreover, the CBus
             library components do not allow side effects as part of accessing the registers through
             the config bus. This library contains modules which will allow side effects.

*/
package CBWire;
`ifdef async_reset
  import RegOverrides  :: *;
`endif
import ModuleCollect::*;
import CBus::*;
import DefaultValue::*;

module wireCB#(Bit#(sa) wire_addr, Bit#(TLog#(sd)) offset)(IWithCBus#(CBus#(sa, sd), Wire#(r)))
provisos (Bits#(r, sr));

  Wire#(r) x <- mkWire;

  interface CBus cbus_ifc;
    method ActionValue#(Bool) write(Bit#(sa) addr, Bit#(sd) data, Bit#(TDiv#(sd,8)) strobe);
      if (addr == wire_addr)
        $display("Warning: attempt to write to a read only config bus at addr %x at time ", addr,
                  $time);
      return False;
    endmethod

    method ActionValue#(Tuple2#(Bit#(sd), Bool)) read(Bit#(sa) addr);
      if (addr == wire_addr)
      begin
        Bit#(sd) shifted = zeroExtendNP(pack(x)) << offset;
        return tuple2(shifted, True);
      end
      else
        return tuple2(0, False);
    endmethod
  endinterface

  interface Wire device_ifc;
    method Action _write (value);
      x <= value;
    endmethod

    method _read = x._read;
  endinterface

endmodule

//Read only Wire module that will connect to CBus. Read has an implicit condition.
//Use this when you want to connect signals from your device directly to a read only config address.
module [ModWithCBus#(sa, sd)] mkCBWireR#(CRAddr#(sa2,sd) addr)(Wire#(r))
provisos (Bits#(r, sr), Add#(ignore, sa2, sa));
  Bit#(sa)        wire_addr   = {0, addr.a};
  Bit#(TLog#(sd)) wire_offset = {0, addr.o};
  let ifc();
  collectCBusIFC#(wireCB(wire_addr, wire_offset)) _temp(ifc);
  return(ifc);
endmodule


////////////////////////////////////////////////////////////////////////////////////////////////////

module nullCBR_withAV#(Bit#(sa) wire_addr, Bit#(TLog#(sd)) offset, ActionValue#(Bit#(sav)) av)
(IWithCBus#(CBus#(sa, sd), Empty));

  interface CBus cbus_ifc;
    method ActionValue#(Bool) write(Bit#(sa) addr, Bit#(sd) data, Bit#(TDiv#(sd,8)) strobe);
      if (addr == wire_addr)
        $display("Warning: attempt to write to a read only config bus at addr %x at time ", addr,
                 $time);
      return False;
    endmethod

    method ActionValue#(Tuple2#(Bit#(sd), Bool)) read(Bit#(sa) addr);
      if (addr == wire_addr)
      begin
        let lv <- av;
        Bit#(sd) shifted = zeroExtendNP(pack(lv)) << offset;
        return tuple2(shifted, True);
      end
      else
        return tuple2(0, False);
    endmethod
  endinterface

  interface Empty device_ifc;
  endinterface
endmodule

//A read only actionvalue element that will connect to CBus.
//Use this when you want a read only config address that returns a value from an actionvalue that is
//performed when the read is done.
module [ModWithCBus#(sa, sd)] mkCBNullR_withAV#(CRAddr#(sa2,sd) addr, ActionValue#(Bit#(sav)) av)(Empty)
provisos (Add#(ignore, sa2, sa));
  Bit#(sa)        wire_addr   = {0, addr.a};
  Bit#(TLog#(sd)) wire_offset = {0, addr.o};
  let ifc();
  collectCBusIFC#(nullCBR_withAV(wire_addr, wire_offset, av)) _temp(ifc);
  return(ifc);
endmodule


////////////////////////////////////////////////////////////////////////////////////////////////////

module rwireCBW#(Bit#(sa) wire_addr, Bit#(TLog#(sd)) offset)(IWithCBus#(CBus#(sa, sd), RWire#(r)))
provisos (Bits#(r, sr));

  RWire#(r) x <- mkRWire;
  PulseWire written <- mkPulseWire;

  interface CBus cbus_ifc;
    method ActionValue#(Bool) write(Bit#(sa) addr, Bit#(sd) data, Bit#(TDiv#(sd,8)) strobe);  //TODO add strobe functionality
      if (addr == wire_addr)
      begin
        let shifted = data >> offset;        //TODO add support for strobe
        x.wset(unpack(truncateNP(shifted)));
        written.send; // give cbus write priority over device _write.
        return True;
      end
      else
        return False;
    endmethod

    method ActionValue#(Tuple2#(Bit#(sd), Bool)) read(Bit#(sa) addr);
      if (addr == wire_addr)
      begin
        $display("Warning: attempt to read to a write only config bus at addr %x at time ", addr, $time);
      end
      return tuple2(0, False);
    endmethod
  endinterface

  interface RWire device_ifc;
    method Action wset (value);
      if(!written) x.wset(value);
    endmethod

    method wget = x.wget;
  endinterface

endmodule

//A write only Wire with no implicit conditions that can connect to CBus.
//Use this when you do not want any register to be instantiated at a config address, but would like
//to send the value written at the config address directly to the device.
module [ModWithCBus#(sa, sd)] mkCBRWireW#(CRAddr#(sa2,sd) addr)(RWire#(r))
  provisos (Bits#(r, sr), Add#(ignore, sa2, sa));
  Bit#(sa)      wire_addr  = {0, addr.a};
  Bit#(TLog#(sd)) wire_offset = {0, addr.o};
  let ifc();
  collectCBusIFC#(rwireCBW(wire_addr, wire_offset)) _temp(ifc);
  return(ifc);
endmodule
endpackage
