// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Tuesday 21 April 2020 09:42:55 AM IST

*/
package DCBus;

`ifdef async_reset
  import RegOverrides  :: *;
`endif
import FIFOF         :: * ;
import Vector        :: * ;
import SpecialFIFOs  :: * ;
import FIFOF         :: * ;
import BUtils        :: * ;
import Memory        :: * ;
import Clocks        :: * ;
import List          :: * ;
import ModuleCollect :: * ;

import apb           :: * ;
import axi4l         :: * ;
import axi4          :: * ;
import Semi_FIFOF    :: * ;
import DefaultValue  :: * ;

`include "Logger.bsv"

typedef enum {Sz1 = 0 , Sz2 = 1 , Sz4 = 2 , Sz8 = 3} AccessSize deriving(Bits, Eq, FShow);
typedef enum {PvU = 0 , PvS = 1 , PvH = 2 , PvM = 3} DCBusXperm deriving(Bits, FShow);

/*doc:ifc: This interface is what any device should have*/
interface DCBus #(numeric type aw,numeric type dw);
  method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm );
  method ActionValue#(Bool) write (Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strb, DCBusXperm wperm);
endinterface:DCBus


/*doc:ifc: the bare device will have 3 subinterfaces,
  - dcbus : for accessing the configuration registers within the bus.
  - io    : the interface holding the chip-io signals that need to brought all the way to the PADS
*/
interface IWithDCBus#(type dcbus_IFC, type device_io_ifc);
  interface dcbus_IFC        dcbus;
  interface device_io_ifc    device;
endinterface:IWithDCBus

/*doc:ifc: this interface replaces the dcbus in the IWithDCBus with a slave interface
  - slave    : a bus based protocol like APB, AXI-4Lite, etc for accessing configuration registers
  - io       : the interface holding the chip-io signals that need to brought all the way to the PADS
*/
interface IWithSlave#(type slave_ifc, type device_io_ifc);
  (*prefix=""*)
  interface slave_ifc        slave;
  (*prefix=""*)
  interface device_io_ifc    device;
endinterface:IWithSlave
// ----------------------------------------------------------------------------------------------

// --------------------- typedefs and structs to be used ----------------------------------------
// Define DCBusItem, the type of item to be collected by module collect
typedef DCBus#(aw, dw) DCBusItem #(type aw, type dw);

// Define ModWithDCBus, the type of a module collecting CBusItems
typedef ModuleCollect#(DCBusItem#(aw, dw), i) ModWithDCBus#(type aw, type dw, type i);

typedef struct {
  Bit#(aw)   addr;
  AccessSize min;
  AccessSize max;
  Bit#(os)   mask;
  DCBusXperm rd_perm;
  DCBusXperm wr_perm;
} DCRAddr#(numeric type aw, numeric type os) deriving(Bits, Eq);
// ----------------------------------------------------------------------------------------------


// A module wrapper that adds the CBus to the collection and
// returns only the "front door" interface.
module [ModWithDCBus#(aw, dw)] collectDCBusIFC#(Module#(IWithDCBus#(DCBus#(aw, dw), i)) m)(i);
  IWithDCBus#(DCBus#(aw, dw), i) double_ifc();
  liftModule#(m) _temp(double_ifc);

  addToCollection(double_ifc.dcbus);
  return(double_ifc.device);
endmodule

// A module wrapper that takes a module with a normal interface,
// processes the collected CBusItems and provides an IWithCBus interface.
module [Module] exposeDCBusIFC#(ModWithDCBus#(aw, dw, i) sm) (IWithDCBus#(DCBus#(aw, dw), i));

  IWithCollection#(DCBusItem#(aw, dw), i) collection_ifc();
  exposeCollection#(sm) _temp(collection_ifc);

  Reg#(Bool) dummy <- mkReg(False);
  List#(DCBus#(aw, dw)) item_list = collection_ifc.collection;

  interface DCBus dcbus;
    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);

      function ActionValue#(Bool) ifc_write(DCBus#(aw, dw) item_ifc);
        actionvalue
          let value <- item_ifc.write(addr, data, strobe, wperm);
          return value;
         endactionvalue
      endfunction

      //joinActions(map(ifc_write, item_list));
      let vs <- List::mapM(ifc_write, item_list);
      return(foldt(bool_or, False, vs));
    endmethod

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);

      dummy <= !dummy;

      function ActionValue#(Tuple2#(Bool, Bit#(dw))) ifc_read(DCBus#(aw, dw) item_ifc);
        actionvalue
          let value <- item_ifc.read(addr, size, rperm);
          return value;
        endactionvalue
      endfunction

      /// fold together the read values for all the collected interfaces
      let vs <- List::mapM(ifc_read, item_list);
      return(foldt(tuple2_or, tuple2(False, 0), vs));
    endmethod

  endinterface
  interface device= collection_ifc.device;
endmodule

// ----------------------------- helper functions -----------------------------------------------
function a foldt(function a f(a x1, a x2), a x, List#(a) xs);
  case (xs) matches
    tagged Nil: return (x);
    default   : return (List::fold(f, xs));
  endcase
endfunction

function Tuple2#(Bool, Bit#(dw)) tuple2_or (Tuple2#(Bool, Bit#(dw)) x, Tuple2#(Bool, Bit#(dw)) y);
  Bit#(dw) lv2 = tpl_2(x) | tpl_2(y);
  Bool    lv1 = tpl_1(x) || tpl_1(y);
  return tuple2(lv1, lv2);
endfunction

function Bool bool_or (Bool x, Bool y);
  return (x || y);
endfunction

function AccessSize strb2size_2(Bit#(n) strb)
  provisos(Add#(a__, n, 8));
  Bit#(8) _t = zeroExtend(strb);
  Bool isSz4 = ((_t>>3)&_t) != 0;
  Bool isSz2 = ((_t>>1)&_t) != 0;
  if (&_t == 1) return Sz8;
  else if (isSz4) return Sz4;
  else if (isSz2) return Sz2;
  else return Sz1;
endfunction

function AccessSize strb2size(Bit#(n) strb)
  provisos(Add#(a__, n, 8));
  Bit#(8) s = zeroExtend(strb);
  Bit#(4) _t = {&s[7:6],&s[5:4],&s[3:2],&s[1:0]};
  Bit#(2) __t = {&_t[3:2],&_t[1:0]};
  Bit#(1) ___t = &__t;
  if( |_t == 0) return Sz1;
  else if ( |__t == 0) return Sz2;
  else if (|___t == 0) return Sz4;
  else return Sz8;
endfunction:strb2size

function AccessSize dw2size(Integer dw);
  if (dw == 8)
    return Sz1;
  else if (dw == 16)
    return Sz2;
  else if (dw == 32)
    return Sz4;
  else
    return Sz8;
endfunction:dw2size

function Reg#(t) readOnlyReg(t r);
  return (interface Reg;
            method t _read = r;
            method Action _write(t x) = noAction;
          endinterface);
endfunction:readOnlyReg

function Reg#(t) writeOnlyReg(t r)
  provisos(Bits#(t, st));
  return (interface Reg;
            method _read = unpack(0);
            method Action _write(t x) = noAction;
          endinterface);
endfunction:writeOnlyReg

function Reg#(t) writeSideEffect(Reg#(t) r, Action a);
    return (interface Reg;
            method t _read = r._read;
            method Action _write(t x);
                r._write(x);
                a;
            endmethod
        endinterface);
endfunction:writeSideEffect

/*doc:func: this is a combination of zeroExtend and truncate. If the input size is larger than the output
 * size, then it is truncated, else it zeroExtend*/
function Bit#(m) reSize (Bit#(n) din) provisos( Add#(m,n,mn) );
  Bit#(mn) x = zeroExtend(din);
  return truncate(x);
endfunction:reSize

(*noinline*)
function DCBusXperm prot_ncode(Bit#(2) axprot);
  return unpack({~axprot[1], axprot[0]});
endfunction:prot_ncode

/*doc:instance: Instance default Value for DCBusXperm enum */
instance DefaultValue #(DCBusXperm);
  defaultValue = PvU;
endinstance

instance Eq#(DCBusXperm)
  provisos(Bits#(DCBus::DCBusXperm, m));
  function Bool \== (DCBusXperm x1, DCBusXperm x2);
    Bit#(m) i = pack(x1);
    Bit#(m) j = pack(x2);
    return i == j;
  endfunction
endinstance
instance Ord#(DCBusXperm)
  provisos(Bits#(DCBus::DCBusXperm, m));
  function Bool \>= (DCBusXperm x1, DCBusXperm x2);
    Bit#(m) i = pack(x1);
    Bit#(m) j = pack(x2);
    return i>=j;
  endfunction
endinstance

/*doc:instance: Instance Ordering class for AccessSize enum */
instance Ord#(AccessSize)
  provisos(Bits#(DCBus::AccessSize, n));
  function Bool \< (AccessSize in1, AccessSize in2);
    Bit#(n) i = pack(in1);
    Bit#(n) j = pack(in2);
    return i<j;
  endfunction

  function Bool \> (AccessSize in1, AccessSize in2);
    Bit#(n) i = pack(in1);
    Bit#(n) j = pack(in2);
    return i>j;
  endfunction

  function Bool \<= (AccessSize in1, AccessSize in2);
    Bit#(n) i = pack(in1);
    Bit#(n) j = pack(in2);
    return i<=j;
  endfunction

  function Bool \>= (AccessSize in1, AccessSize in2);
    Bit#(n) i = pack(in1);
    Bit#(n) j = pack(in2);
    return i>=j;
  endfunction

endinstance

/*doc:func:
address = the full address received on the bus
sz      = size of the operation requested on the Bus
data    = value currently present in the register
allowed = statically defined value indicating the smallest size read that is allowed on this register
mask    = even though the allowed indicates the size of op allowed, multiple such ops can exist within
          the same register. For. consider regB is a 8-bit register, with allowed =  Sz1. Now this
          function is called when the index hits on regA. Within the 8 bytes allotted to regB, the
          read operation could be for any other byte. But we want to perform a read only if the request is
          at the lowest byte. We achieve this by having a 3-bit mask of 000 which is checked against
          the lower 3 bits of the address.
notes: when the bus-side is larger than the register then byte-shifts are not required since the
data in the register is correctly byte-aligned to a 8-byte boundary.
notes: when the bus-side is smalles than the register side, then the rregister contents have to be
properly byte shifted to ensure the correct bytes are sent back to the bus.
 */

function Tuple2#(Bool,Bit#(n)) fn_adjust_read(Bit#(a) addr,
                                              AccessSize sz,
                                              Bit#(m) data,
                                              AccessSize min,
                                              AccessSize max,
                                              Bit#(os) mask)
  provisos(
    Add#(a__, os, a),
    Mul#(TDiv#(n, 8), 8, n), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(n, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(n)),0,n), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(d__, TDiv#(n, 8), 8)
  );
  let mi = valueOf(m);
  let ni = valueOf(n);
  Bit#(os) byteoffset = truncate(addr);
  Bool offset_match  = (mask | byteoffset) == mask;
  Bit#(os) _zeros = 0;
  if (mi > ni)
    data = data >> {byteoffset,_zeros};
  Bool access_allowed = (min <= sz) && (sz <= max);
  if (access_allowed && offset_match) return tuple2(True, reSize(data));
  else return tuple2(False,0);
endfunction:fn_adjust_read

/*doc:func:
address = the full address received on the bus
newdata = the full data received on the bus
strb    = the sull strobe bits received on the bus
data    = value currently present in the register
allowed = statically defined value indicating the smallest size read that is allowed on this register
mask    = even though the allowed indicates the size of op allowed, multiple such ops can exist within
          the same register. For. consider regB is a 8-bit register, with allowed =  Sz1. Now this
          function is called when the index hits on regA. Within the 8 bytes allotted to regB, the
          read operation could be for any other byte. But we want to perform a read only if the request is
          at the lowest byte. We achieve this by having a 3-bit mask of 000 which is checked against
          the lower 3 bits of the address.
notes: when the bus-side is smaller than the register side, then the bus-side contents and strobes
have to be properly byte shifted to ensure the correct bytes are updated in the larger register.
 */
function ActionValue#(Tuple2#(Bool,Bit#(m))) fn_adjust_write(Bit#(a) addr,
                              Bit#(n) newdata,
                              Bit#(TDiv#(n,8)) strb,
                              Bit#(m) data,
                              AccessSize min,
                              AccessSize max,
                              Bit#(os) mask)
  provisos(
    Add#(a__, os, a),
    Mul#(TDiv#(n, 8), 8, n), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(n, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(n)),0,n), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(d__, TDiv#(n, 8), 8),

    Add#(TSub#(2, TLog#(TDiv#(n, 8))), e__, os)
  ) = actionvalue

  let mi = valueOf(m);
  let ni = valueOf(n);

  let sz = strb2size_2(strb);

  Bit#(os) byteoffset = truncate(addr);
  Bool offset_match  = (mask | byteoffset) == mask;

  Bit#(m) newdata1 = reSize(newdata);
  Bit#(TDiv#(m,8)) newstrb1 = reSize(strb);
  Bit#(3) _zeros = 0;

  if(mi > ni) begin
    if(byteoffset != 0) begin
      newdata1 = newdata1 << {byteoffset,_zeros};
      newstrb1 = newstrb1 << byteoffset;
    end
  end

  Bit#(m) upd_data;
  upd_data = updateDataWithMask(data, newdata1, newstrb1);
  Bool access_allowed = min <= sz && sz <= max;
  if (access_allowed && offset_match) return tuple2(True, upd_data);
  else return tuple2(False,upd_data);
endactionvalue;

// ------------------------------ Regular Read-write register ------------------------------------
module regRW#(DCRAddr#(aw,o) attr, r reset)(IWithDCBus#(DCBus#(aw, dw), Reg#(r)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );

  Reg#(r) x();
  mkReg#(reset) inner_reg(x);
  PulseWire written <- mkPulseWire;

  interface DCBus dcbus;
    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
      if ((req_index == reg_index) && perm) begin
        let {succ, temp} <- fn_adjust_write(addr, data, strobe, pack(x), attr.min, attr.max, attr.mask);
        if(succ) begin x<= unpack(temp); written.send; end // give cbus write priority over device _write.
        return succ;
      end
      else
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
      if ((req_index == reg_index) && perm) begin
        let temp = fn_adjust_read(addr, size, pack(x), attr.min, attr.max, attr.mask );
        return temp;
      end
      else
        return tuple2(False, 0);
    endmethod:read
  endinterface:dcbus
  interface Reg device;
    method Action _write (value);
      if (!written) x <= value;
    endmethod:_write
    method _read = x._read;
  endinterface
endmodule:regRW

// A wrapper to provide just a normal Reg interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal register would be used).
module [ModWithDCBus#(aw, dw)] mkDCBRegRW#(DCRAddr#(aw,o) attr, r x)(Reg#(r))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );
  let ifc();
  collectDCBusIFC#(regRW(attr, x)) _temp(ifc);
  return(ifc);
endmodule:mkDCBRegRW
// ------------------------------------------------------------------------------------------------

// ------------------------------ Read-Only register ------------------------------------
module regRO#(DCRAddr#(aw,o) attr, r reset)(IWithDCBus#(DCBus#(aw, dw), Reg#(r)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );

  Reg#(r) x();
  mkReg#(reset) inner_reg(x);
  PulseWire written <- mkPulseWire;

  interface DCBus dcbus;

    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
      if ((req_index == reg_index) && perm) begin
        let temp = fn_adjust_read(addr, size, pack(x), attr.min, attr.max, attr.mask );
        return temp;
      end
      else
        return tuple2(False, 0);
    endmethod:read
  endinterface:dcbus

  interface Reg device;
    method Action _write (value);
      x <= value;
    endmethod:_write

    method _read = x._read;
  endinterface
endmodule:regRO

// A wrapper to provide just a normal Reg interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal register would be used).
module [ModWithDCBus#(aw, dw)] mkDCBRegRO#(DCRAddr#(aw,o) attr, r x)(Reg#(r))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );
  let ifc();
  collectDCBusIFC#(regRO(attr, x)) _temp(ifc);
  return(ifc);
endmodule:mkDCBRegRO
// ------------------------------------------------------------------------------------------------

// ------------------------------ Write-Only register ------------------------------------

// One basic configuration register with RW capabilities.
module regWO#(DCRAddr#(aw,o) attr, r reset)(IWithDCBus#(DCBus#(aw, dw), Reg#(r)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );

  Reg#(r) x();
  mkReg#(reset) inner_reg(x);
  PulseWire written <- mkPulseWire;

  interface DCBus dcbus;

    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
      if ((req_index == reg_index) && perm) begin
        let {succ, temp} <- fn_adjust_write(addr, data, strobe, 0, attr.min, attr.max, attr.mask);
        if(succ) begin x<= unpack(temp); written.send; end // give cbus write priority over device _write.
        return succ;
      end
      else
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
        return tuple2(False, 0);
    endmethod:read
  endinterface:dcbus

  interface Reg device;
    method Action _write (value);
      if (!written) x <= value;
    endmethod:_write

    method _read = x._read;
  endinterface
endmodule:regWO

// A wrapper to provide just a normal Reg interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal register would be used).
module [ModWithDCBus#(aw, dw)] mkDCBRegWO#(DCRAddr#(aw,o) attr, r x)(Reg#(r))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );
  let ifc();
  collectDCBusIFC#(regWO(attr, x)) _temp(ifc);
  return(ifc);
endmodule:mkDCBRegWO
// ------------------------------------------------------------------------------------------------

/// ------------------------------ ReadOnly-SideEffect register ------------------------------------

// One basic configuration register with RW capabilities.
module regROSe#(DCRAddr#(aw,o) attr, r reset, Action _act)(IWithDCBus#(DCBus#(aw, dw), Reg#(r)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );

  Reg#(r) x();
  mkReg#(reset) inner_reg(x);
  PulseWire written <- mkPulseWire;

  interface DCBus dcbus;
    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
      if ((req_index == reg_index) && perm) begin
        Tuple2#(Bool,Bit#(dw)) temp = fn_adjust_read(addr, size, pack(x), attr.min, attr.max, attr.mask );
        if(tpl_1(temp)) begin _act; end
        return temp;
      end
      else
        return tuple2(False, 0);
    endmethod:read
  endinterface:dcbus

  interface Reg device;
    method Action _write (value);
      if (!written) x <= value;
    endmethod:_write

    method _read = x._read;
  endinterface
endmodule:regROSe

// A wrapper to provide just a normal Reg interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal register would be used).
module [ModWithDCBus#(aw, dw)] mkDCBRegROSe#(DCRAddr#(aw,o) attr, r x, Action _act)(Reg#(r))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );
  let ifc();
  collectDCBusIFC#(regROSe(attr, x, _act)) _temp(ifc);
  return(ifc);
endmodule:mkDCBRegROSe
// ------------------------------------------------------------------------------------------------

/// ------------------------------ Write-SideEffect register ------------------------------------

// One basic configuration register with RW capabilities.
module regRWSe#(DCRAddr#(aw,o) attr, r reset, Action _act)(IWithDCBus#(DCBus#(aw, dw), Reg#(r)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );

  Reg#(r) x();
  mkReg#(reset) inner_reg(x);
  PulseWire written <- mkPulseWire;

  interface DCBus dcbus;
    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
      if ((req_index == reg_index) && perm) begin
        let {succ, temp} <- fn_adjust_write(addr, data, strobe, pack(x), attr.min, attr.max, attr.mask);
        if(succ) begin x<= unpack(temp); written.send; _act; end // give cbus write priority over device _write.
        return succ;
      end
      else
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
      if ((req_index == reg_index) && perm) begin
        let temp = fn_adjust_read(addr, size, pack(x), attr.min, attr.max, attr.mask );
        return temp;
      end
      else
        return tuple2(False, 0);
    endmethod:read
  endinterface:dcbus

  interface Reg device;
    method Action _write (value);
      if (!written) x <= value;
    endmethod:_write

    method _read = x._read;
  endinterface
endmodule:regRWSe

// A wrapper to provide just a normal Reg interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal register would be used).
module [ModWithDCBus#(aw, dw)] mkDCBRegRWSe#(DCRAddr#(aw,o) attr, r x, Action _act)(Reg#(r))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );
  let ifc();
  collectDCBusIFC#(regRWSe(attr, x, _act)) _temp(ifc);
  return(ifc);
endmodule:mkDCBRegRWSe
// ------------------------------------------------------------------------------------------------

module rwireW#(DCRAddr#(aw,o) attr)(IWithDCBus#(DCBus#(aw, dw), RWire#(r)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );

  RWire#(r) x <- mkRWire;
  PulseWire written <- mkPulseWire;

  interface DCBus dcbus;
    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
      if ((req_index == reg_index) && perm) begin
        let {succ, temp} <- fn_adjust_write(addr, data, strobe, 0, attr.min, attr.max, attr.mask);
        if(succ) begin x.wset(unpack(temp)); written.send; end // give cbus write priority over device _write.
        return succ;
      end
      else
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
        return tuple2(False, 0);
    endmethod
  endinterface

  interface RWire device;
    method Action wset (value);
      if(!written) x.wset(value);
    endmethod

    method wget = x.wget;
  endinterface
endmodule:rwireW

//A write only Wire with no implicit conditions that can connect to CBus.
//Use this when you do not want any register to be instantiated at a config address, but would like
//to send the value written at the config address directly to the device.
module [ModWithDCBus#(aw, dw)] mkDCBRWireW#(DCRAddr#(aw,o) attr)(RWire#(r))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );
  let ifc();
  collectDCBusIFC#(rwireW(attr)) _temp(ifc);
  return(ifc);
endmodule:mkDCBRWireW

module bypasswireROSe#(DCRAddr#(aw,o) attr, Action _act)(IWithDCBus#(DCBus#(aw, dw), Wire#(r)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );

  Wire#(r) x <- mkBypassWire();

  interface DCBus dcbus;
    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
      if ((req_index == reg_index) && perm) begin
        Tuple2#(Bool,Bit#(dw)) temp = fn_adjust_read(addr, size, pack(x._read), attr.min, attr.max, attr.mask );
        if(tpl_1(temp)) _act;
        return temp;
      end
      else
        return tuple2(False, 0);
    endmethod:read
  endinterface

  interface Wire device;
    method Action _write (value);
      x._write(value);
    endmethod

    method _read = x._read;
  endinterface
endmodule:bypasswireROSe

//A write only Wire with no implicit conditions that can connect to CBus.
//Use this when you do not want any register to be instantiated at a config address, but would like
//to send the value written at the config address directly to the device.
module [ModWithDCBus#(aw, dw)] mkDCBBypassWireROSe#(DCRAddr#(aw,o) attr, Action _act)(Wire#(r))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );
  let ifc();
  collectDCBusIFC#(bypasswireROSe(attr, _act)) _temp(ifc);
  return(ifc);
endmodule:mkDCBBypassWireROSe

module bypasswireRO#(DCRAddr#(aw,o) attr)(IWithDCBus#(DCBus#(aw, dw), Wire#(r)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );

  Wire#(r) x <- mkBypassWire();

  interface DCBus dcbus;
    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
      if ((req_index == reg_index) && perm) begin
        let temp = fn_adjust_read(addr, size, pack(x._read), attr.min, attr.max, attr.mask );
        return temp;
      end
      else
        return tuple2(False, 0);
    endmethod:read
  endinterface

  interface Wire device;
    method Action _write (value);
      x._write(value);
    endmethod

    method _read = x._read;
  endinterface

endmodule:bypasswireRO

//A write only Wire with no implicit conditions that can connect to CBus.
//Use this when you do not want any register to be instantiated at a config address, but would like
//to send the value written at the config address directly to the device.
module [ModWithDCBus#(aw, dw)] mkDCBBypassWireRO#(DCRAddr#(aw,o) attr)(Wire#(r))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );
  let ifc();
  collectDCBusIFC#(bypasswireRO(attr)) _temp(ifc);
  return(ifc);
endmodule:mkDCBBypassWireRO


/*doc:module: If the source and destination clocks are the same, then this module simple
 * instantiates a wire between the enq-deq. if the clocks are different then a synchronizer is used.
*/
module mkBypassSyncFromCC #(Integer depth, Clock dest_clock)(FIFOF#(d))
  provisos( Bits#(d,a__));

  Clock cur_clk<-exposeCurrentClock;
  Reset cur_rst<-exposeCurrentReset;
  Bool sync_required=(cur_clk != dest_clock);

  if (sync_required)  begin
    SyncFIFOIfc#(d) ff_req    <- mkSyncFIFOFromCC(depth,dest_clock);
    method Action enq ( d data) ;
      ff_req.enq(data);
    endmethod: enq

    method deq      = ff_req.deq;
    method first    = ff_req.first;
    method notFull  = ff_req.notFull;
    method notEmpty = ff_req.notEmpty;
    method clear = noAction;
  end
  else begin
    FIFOF#(d) ff_req <- mkBypassFIFOF();

    method Action enq ( d data) ;
      ff_req.enq(data);
    endmethod: enq

    method deq      = ff_req.deq;
    method first    = ff_req.first;
    method notFull  = ff_req.notFull;
    method notEmpty = ff_req.notEmpty;
    method clear = noAction;
  end
endmodule:mkBypassSyncFromCC

/*doc:module: If the source and destination clocks are the same, then this module simple
 * instantiates a wire between the enq-deq. if the clocks are different then a synchronizer is used.
*/
module mkBypassSyncToCC #(Integer depth, Clock src_clock, Reset src_reset)(FIFOF#(d))
  provisos( Bits#(d,a__));

  Clock cur_clk<-exposeCurrentClock;
  Reset cur_rst<-exposeCurrentReset;
  Bool sync_required=(cur_clk != src_clock);

  if (sync_required)  begin
    SyncFIFOIfc#(d) ff_req    <- mkSyncFIFOToCC(depth, src_clock, src_reset);
    method Action enq ( d data) ;
      ff_req.enq(data);
    endmethod: enq

    method deq      = ff_req.deq;
    method first    = ff_req.first;
    method notFull  = ff_req.notFull;
    method notEmpty = ff_req.notEmpty;
    method clear = noAction;
  end
  else begin
    Wire#(d)        wr_req    <- mkWire();
    PulseWire       enquing   <- mkPulseWire;
    method Action enq (d data) ;
      wr_req <= data;
      enquing.send;
    endmethod: enq

    method deq      = noAction;
    method first    = wr_req;
    method notFull  = True;
    method notEmpty = enquing._read;
    method clear = noAction;
  end
endmodule:mkBypassSyncToCC

/*doc:mod: This module takes a submodule with IWithDCBus interface and replaces the DCBus
* interface with an APB interface of the same size*/
module [Module] dc2apb #(module#(IWithDCBus#(DCBus#(aw,dw), _io)) device,
                        parameter Integer base, Clock device_clk, Reset device_rst)
  (IWithSlave#(Ifc_apb_slave#(aw, dw, uw),_io));

  IWithDCBus#(DCBus#(aw,dw), _io) device_ifc();
  liftModule#(device) _temp(device_ifc);

  DCBus#(aw,dw) device_dcbus = device_ifc.dcbus;
  _io lv_device_io = device_ifc.device;

  Ifc_apb_slave_xactor#(aw, dw, uw) s_xactor <- mkapb_slave_xactor;

  Clock cur_clk<-exposeCurrentClock;
  Reset cur_rst<-exposeCurrentReset;
  Bool sync_required=(cur_clk != device_clk);

  if (sync_required) begin
    SyncFIFOIfc#(APB_request#(aw,dw,uw)) ff_sync_req  <- mkSyncFIFOFromCC(3, device_clk);
    SyncFIFOIfc#(APB_response#(dw,uw))   ff_sync_resp <- mkSyncFIFOToCC(3, device_clk, device_rst);

    /*doc:rule: */
    rule rl_pop_apb_req;
      let req <- pop_o(s_xactor.fifo_side.o_request);
      ff_sync_req.enq(req);
      `logLevel( dc2apb, 0, $format("DC2APB: SyncReq:",fshow_apb_req(req)))
    endrule:rl_pop_apb_req

    /*doc:rule: */
    rule rl_req_to_device;
      let req = ff_sync_req.first;
      ff_sync_req.deq;
      APB_response#(dw, uw) resp;
      `logLevel( dc2apb, 1, $format("DC2APB: Req:", fshow_apb_req(req)))
      if (req.pwrite) begin // write operation
        let succ <- device_dcbus.write(req.paddr - fromInteger(base), req.pwdata, req.pstrb,
                                       prot_ncode(truncate(req.prot)));
        resp= APB_response{ pslverr: !succ, prdata: ?, puser:req.puser};
        `logLevel( dc2apb, 1, $format("DC2APB: Write Resp:", fshow_apb_resp(resp)))
      end
      else begin  //read operation
        let {succ, rdata}<- device_dcbus.read(req.paddr - fromInteger(base), dw2size(valueOf(dw)),
                                              prot_ncode(truncate(req.prot)) );
        resp= APB_response{ pslverr: !succ, prdata: zeroExtend(rdata), puser:req.puser};
        `logLevel( dc2apb, 1, $format("DC2APB: Read Resp:", fshow_apb_resp(resp)))
      end
      ff_sync_resp.enq(resp);
    endrule:rl_req_to_device

    /*doc:rule: */
    rule rl_push_apb_resp;
      s_xactor.fifo_side.i_response.enq(ff_sync_resp.first);
      ff_sync_resp.deq;
      `logLevel( dc2apb, 0, $format("DC2APB: SyncResp:",fshow_apb_resp(ff_sync_resp.first)))
    endrule:rl_push_apb_resp
  end
  else begin
    /*doc:rule: */
    rule rl_pop_apb_req;
      let req <- pop_o(s_xactor.fifo_side.o_request);
      `logLevel( dc2apb, 1, $format("DC2APB: Req:", fshow_apb_req(req)))
      APB_response#(dw, uw) resp;
      if (req.pwrite) begin // write operation
        let succ <- device_dcbus.write(req.paddr - fromInteger(base), req.pwdata, req.pstrb,
                                        prot_ncode(truncate(req.prot)));
        resp= APB_response{ pslverr: !succ, prdata: ?, puser:req.puser};
        `logLevel( dc2apb, 1, $format("DC2APB: Write Resp:", fshow_apb_resp(resp)))
      end
      else begin  //read operation
        let {succ, rdata}<- device_dcbus.read(req.paddr - fromInteger(base), dw2size(valueOf(dw)),
                                              prot_ncode(truncate(req.prot)));
        resp= APB_response{ pslverr: !succ, prdata: zeroExtend(rdata), puser:req.puser};
        `logLevel( dc2apb, 1, $format("DC2APB: Read Resp:", fshow_apb_resp(resp)))
      end
      s_xactor.fifo_side.i_response.enq(resp);
    endrule:rl_pop_apb_req
  end

  interface slave= s_xactor.apb_side;
  interface device= lv_device_io;

endmodule:dc2apb

/*doc:mod: This module takes a submodule with IWithDCBus interface and replaces the DCBus
* interface with an APB interface of the same size*/
module [Module] dc2axi4l #(module#(IWithDCBus#(DCBus#(aw,dw), _io)) device,
                           parameter Integer base, Clock device_clk, Reset device_rst)
  (IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw),_io));

  IWithDCBus#(DCBus#(aw,dw), _io) device_ifc();
  liftModule#(device) _temp(device_ifc);

  DCBus#(aw,dw) device_dcbus = device_ifc.dcbus;
  _io lv_device_io = device_ifc.device;

  Ifc_axi4l_slave_xactor#(aw, dw, uw) s_xactor <- mkaxi4l_slave_xactor_2;

  Clock cur_clk<-exposeCurrentClock;
  Reset cur_rst<-exposeCurrentReset;
  Bool sync_required=(cur_clk != device_clk);

  if (sync_required) begin

    SyncFIFOIfc#(Axi4l_rd_addr#(aw,uw)) ff_sync_rd_req   <- mkSyncFIFOFromCC(3, device_clk);
    SyncFIFOIfc#(Axi4l_wr_addr#(aw,uw)) ff_sync_wr_req   <- mkSyncFIFOFromCC(3, device_clk);
    SyncFIFOIfc#(Axi4l_wr_data#(dw))    ff_sync_wrd_req  <- mkSyncFIFOFromCC(3, device_clk);
    SyncFIFOIfc#(Axi4l_rd_data#(dw,uw)) ff_sync_rd_resp  <- mkSyncFIFOToCC(3, device_clk, device_rst);
    SyncFIFOIfc#(Axi4l_wr_resp#(uw))    ff_sync_wr_resp  <- mkSyncFIFOToCC(3, device_clk, device_rst);

    /*doc:rule: */
    rule rl_pop_axi4l_rd_req;
      let req <- pop_o(s_xactor.fifo_side.o_rd_addr);
      ff_sync_rd_req.enq(req);
      `logLevel( dc2axi4l, 0, $format("DC2AXI4L: RdSyncReq:",fshow_axi4l_rd_addr(req)))
    endrule:rl_pop_axi4l_rd_req

    /*doc:rule: */
    rule rl_pop_axi4l_wr_req;
      let req <- pop_o(s_xactor.fifo_side.o_wr_addr);
      let reqd <- pop_o(s_xactor.fifo_side.o_wr_data);
      ff_sync_wr_req.enq(req);
      ff_sync_wrd_req.enq(reqd);
      `logLevel( dc2axi4l, 0, $format("DC2AXI4L: WrSyncReq:",fshow_axi4l_wr_addr(req)))
      `logLevel( dc2axi4l, 0, $format("DC2AXI4L: WrDSyncReq:",fshow_axi4l_wr_data(reqd)))
    endrule:rl_pop_axi4l_wr_req

    /*doc:rule: */
    rule rl_rd_req_to_device;
      let req = ff_sync_rd_req.first;
      ff_sync_rd_req.deq;
      `logLevel( dc2apb, 1, $format("DC2AXI4L: RdReq:", fshow_axi4l_rd_addr(req)))
      let {succ, rdata}<- device_dcbus.read(req.araddr - fromInteger(base), dw2size(valueOf(dw)),
                                            prot_ncode(truncate(req.arprot)));
      let lv_resp= Axi4l_rd_data {rresp: succ? axi4l_resp_okay : axi4l_resp_slverr,
                                  rdata: rdata, ruser: req.aruser};
      `logLevel( dc2apb, 1, $format("DC2AXI4L: Read Resp:", fshow_axi4l_rd_data(lv_resp)))
      ff_sync_rd_resp.enq(lv_resp);
    endrule:rl_rd_req_to_device

    /*doc:rule: */
    rule rl_wr_req_to_device;
      let req = ff_sync_wr_req.first;
      let reqd = ff_sync_wrd_req.first;
      ff_sync_wr_req.deq;
      ff_sync_wrd_req.deq;
      `logLevel( dc2apb, 1, $format("DC2AXI4L: WrReq:", fshow_axi4l_wr_addr(req)))
      let succ<- device_dcbus.write(req.awaddr - fromInteger(base), reqd.wdata, reqd.wstrb,
                                    prot_ncode(truncate(req.awprot)));
      let lv_resp= Axi4l_wr_resp {bresp: succ? axi4l_resp_okay : axi4l_resp_slverr,
                                  buser: req.awuser};
      `logLevel( dc2apb, 1, $format("DC2AXI4L: Write Resp:", fshow_axi4l_wr_resp(lv_resp)))
      ff_sync_wr_resp.enq(lv_resp);
    endrule:rl_wr_req_to_device

    /*doc:rule: */
    rule rl_push_rd_axi4l_resp;
      s_xactor.fifo_side.i_rd_data.enq(ff_sync_rd_resp.first);
      ff_sync_rd_resp.deq;
      `logLevel( dc2axi4l, 0, $format("DC2AXI4L: SyncResp:",fshow_axi4l_rd_data(ff_sync_rd_resp.first)))
    endrule:rl_push_rd_axi4l_resp

    /*doc:rule: */
    rule rl_push_wr_axi4l_resp;
      s_xactor.fifo_side.i_wr_resp.enq(ff_sync_wr_resp.first);
      ff_sync_wr_resp.deq;
      `logLevel( dc2axi4l, 0, $format("DC2AXI4L: SyncResp:",fshow_axi4l_wr_resp(ff_sync_wr_resp.first)))
    endrule:rl_push_wr_axi4l_resp
  end
  else begin
    /*doc:rule: */
    rule rl_axi4l_rd_req;
      let req <- pop_o(s_xactor.fifo_side.o_rd_addr);
      `logLevel( dc2axi4l, 1, $format("DC2AXI4L: RdReq:", fshow_axi4l_rd_addr(req)))
      let {succ, rdata}<- device_dcbus.read(req.araddr - fromInteger(base), dw2size(valueOf(dw)),
                                            prot_ncode(truncate(req.arprot)));
      let lv_resp= Axi4l_rd_data {rresp: succ? axi4l_resp_okay : axi4l_resp_slverr,
                                  rdata: rdata, ruser: req.aruser};
      `logLevel( dc2axi4l, 1, $format("DC2AXI4L: Read Resp:", fshow_axi4l_rd_data(lv_resp)))
      s_xactor.fifo_side.i_rd_data.enq(lv_resp);
    endrule:rl_axi4l_rd_req

    /*doc:rule: */
    rule rl_axi4l_wr_req;
      let req <- pop_o(s_xactor.fifo_side.o_wr_addr);
      let reqd <- pop_o(s_xactor.fifo_side.o_wr_data);
      `logLevel( dc2axi4l, 1, $format("DC2AXI4L: WrReq:", fshow_axi4l_wr_addr(req)))
      let succ<- device_dcbus.write(req.awaddr - fromInteger(base), reqd.wdata, reqd.wstrb,
                                    prot_ncode(truncate(req.awprot)));
      let lv_resp= Axi4l_wr_resp {bresp: succ? axi4l_resp_okay : axi4l_resp_slverr,
                                  buser: req.awuser};
      `logLevel( dc2axi4l, 1, $format("DC2AXI4L: Write Resp:", fshow_axi4l_wr_resp(lv_resp)))
      s_xactor.fifo_side.i_wr_resp.enq(lv_resp);
    endrule:rl_axi4l_wr_req

  end
  interface slave= s_xactor.axi4l_side;
  interface device= lv_device_io;

endmodule:dc2axi4l


//AXI4 interface -------------------------------------------------------------------------------------------------------------------------------


typedef enum {Idle, Burst} DCFabric_State deriving(Eq, Bits, FShow);

/*doc:mod: This module takes a submodule with IWithDCBus interface and replaces the DCBus
* interface with an AXI4 interface of the same size*/
module [Module] dc2axi4 #(module#(IWithDCBus#(DCBus#(aw,dw), _io)) device,
                          parameter Integer base, Clock device_clk, Reset device_rst)
  (IWithSlave#(Ifc_axi4_slave#(iw,aw, dw, uw),_io));

  IWithDCBus#(DCBus#(aw,dw), _io) device_ifc();
  liftModule#(device) _temp(device_ifc);

  DCBus#(aw,dw) device_dcbus = device_ifc.dcbus;
  _io lv_device_io = device_ifc.device;

  Ifc_axi4_slave_xactor#(iw, aw, dw, uw) s_xactor <- mkaxi4_slave_xactor_2;

  Clock cur_clk<-exposeCurrentClock;
  Reset cur_rst<-exposeCurrentReset;
  Bool sync_required=(cur_clk != device_clk);

  /*doc:reg: */
  Reg#(DCFabric_State) rg_rd_state <- mkReg(Idle, clocked_by device_clk);
  /*doc:reg: */
  Reg#(DCFabric_State) rg_wr_state <- mkReg(Idle, clocked_by device_clk);

  /*doc:reg: hold the request on the read-channel*/
  Reg#(Axi4_rd_addr#(iw, aw, uw)) rg_rd_req <- mkReg(unpack(0), clocked_by device_clk);
  /*doc:reg: hold the request on the read-channel*/
  Reg#(Axi4_wr_addr#(iw, aw, uw)) rg_wr_req <- mkReg(unpack(0), clocked_by device_clk);
  /*doc:reg: count the number of beats performed*/
  Reg#(Bit#(8)) rg_readreq_count<-mkReg(0, clocked_by device_clk);
  /*doc:reg: register holds the temp response for burst writes*/
  Reg#(Axi4_wr_resp	#(iw, uw)) rg_write_response <-mkReg(unpack(0), clocked_by device_clk);

  if (sync_required) begin

    SyncFIFOIfc#(Axi4_rd_addr#(iw,aw,uw)) ff_sync_rd_req   <- mkSyncFIFOFromCC(3, device_clk);
    SyncFIFOIfc#(Axi4_wr_addr#(iw,aw,uw)) ff_sync_wr_req   <- mkSyncFIFOFromCC(3, device_clk);
    SyncFIFOIfc#(Axi4_wr_data#(dw,uw))    ff_sync_wrd_req  <- mkSyncFIFOFromCC(3, device_clk);
    SyncFIFOIfc#(Axi4_rd_data#(iw,dw,uw)) ff_sync_rd_resp  <- mkSyncFIFOToCC(3, device_clk, device_rst);
    SyncFIFOIfc#(Axi4_wr_resp#(iw,uw))    ff_sync_wr_resp  <- mkSyncFIFOToCC(3, device_clk, device_rst);

    /*doc:rule: */
    rule rl_pop_axi4_rd_req;
      let req <- pop_o(s_xactor.fifo_side.o_rd_addr);
      ff_sync_rd_req.enq(req);
      `logLevel( dc2axi4, 0, $format("DC2AXI4: RdSyncReq:",fshow_axi4_rd_addr(req)))
    endrule:rl_pop_axi4_rd_req

    /*doc:rule: */
    rule rl_pop_axi4_wr_req;
      let req <- pop_o(s_xactor.fifo_side.o_wr_addr);
      ff_sync_wr_req.enq(req);
      `logLevel( dc2axi4, 0, $format("DC2AXI4: WrSyncReq:",fshow_axi4_wr_addr(req)))
    endrule:rl_pop_axi4_wr_req

    /*doc:rule: */
    rule rl_pop_axi4_wrd_req;
      let reqd <- pop_o(s_xactor.fifo_side.o_wr_data);
      ff_sync_wrd_req.enq(reqd);
      `logLevel( dc2axi4, 0, $format("DC2AXI4: WrDSyncReq:",fshow_axi4_wr_data(reqd)))
    endrule:rl_pop_axi4_wrd_req

    /*doc:rule: */
    rule rl_rd_req_to_device(rg_rd_state == Idle);
      let req = ff_sync_rd_req.first;
      if(req.arlen != 0)
        rg_rd_state <= Burst;
      ff_sync_rd_req.deq;
      rg_readreq_count <= req.arlen;
	  rg_rd_req <= req;
      `logLevel( dc2axi4, 1, $format("DC2AXI4: RdReq:", fshow_axi4_rd_addr(req)))
      let {succ, rdata}<- device_dcbus.read(req.araddr - fromInteger(base), unpack(truncate(req.arsize)),
                                            prot_ncode(truncate(req.arprot)));
      let lv_resp= Axi4_rd_data {rresp: succ ? axi4_resp_okay : axi4_resp_slverr, rlast: req.arlen==0,
                                  rid: req.arid, rdata: rdata, ruser: req.aruser};
      `logLevel( dc2axi4, 1, $format("DC2AXI4: Read Resp:", fshow_axi4_rd_data(lv_resp)))
      ff_sync_rd_resp.enq(lv_resp);
    endrule:rl_rd_req_to_device

    /*doc:rule: */
    rule rl_rd_burst_request(rg_rd_state == Burst);
  	  if(rg_readreq_count == 1)
  	    rg_rd_state <= Idle;

  	  let address=fn_axi4burst_addr(rg_rd_req.arlen,   rg_rd_req.arsize,
                                    rg_rd_req.arburst, rg_rd_req.araddr);
      rg_rd_req.araddr <= address;
      let {succ, rdata}<- device_dcbus.read(rg_rd_req.araddr - fromInteger(base), unpack(truncate(rg_rd_req.arsize)),
                                            prot_ncode(truncate(rg_rd_req.arprot)));
      rg_readreq_count <= rg_readreq_count - 1;
      let lv_resp= Axi4_rd_data {rresp: succ ? axi4_resp_okay : axi4_resp_slverr, rlast: rg_readreq_count==1, rid:
        rg_rd_req.arid, rdata: rdata, ruser: rg_rd_req.aruser};
      `logLevel( dc2axi4, 1, $format("DC2AXI4: Burst Read Resp:", fshow_axi4_rd_data(lv_resp)))
      ff_sync_rd_resp.enq(lv_resp);
    endrule:rl_rd_burst_request

    /*doc:rule: */
    rule rl_wr_req_to_device(rg_wr_state == Idle);
      let req = ff_sync_wr_req.first;
      let reqd = ff_sync_wrd_req.first;
      ff_sync_wr_req.deq;
      ff_sync_wrd_req.deq;
      `logLevel( dc2axi4, 1, $format("DC2AXI4: WrReq:", fshow_axi4_wr_addr(req)))
      `logLevel( dc2axi4, 1, $format("DC2AXI4: WrDReq:", fshow_axi4_wr_data(reqd)))
      let succ<- device_dcbus.write(req.awaddr - fromInteger(base), reqd.wdata, reqd.wstrb,
                                    prot_ncode(truncate(req.awprot)));
      let lv_resp= Axi4_wr_resp {bresp: succ? axi4_resp_okay : axi4_resp_slverr, bid: req.awid,
                                  buser: req.awuser};
      `logLevel( dc2axi4, 1, $format("DC2AXI4: Write Resp:", fshow_axi4_wr_resp(lv_resp)))
      rg_write_response <= lv_resp;
      if(!reqd.wlast)
        rg_wr_state <= Burst;
      else
        ff_sync_wr_resp.enq(lv_resp);
      rg_wr_req <= req;
    endrule:rl_wr_req_to_device

    rule rl_wr_burst_req_to_device(rg_wr_state==Burst);
      let w  = ff_sync_wrd_req.first;
      ff_sync_wrd_req.deq;
  	  let address=fn_axi4burst_addr(rg_wr_req.awlen,   rg_wr_req.awsize,
                                    rg_wr_req.awburst, rg_wr_req.awaddr);
      `logLevel( dc2axi4, 1, $format("DC2AXI4: Burst WrDReq:", fshow_axi4_wr_data(w)))
      rg_wr_req.awaddr <= address;
      let b = rg_write_response;
      b.buser = w.wuser;
      let succ<- device_dcbus.write(rg_wr_req.awaddr - fromInteger(base), w.wdata, w.wstrb,
                                    prot_ncode(truncate(rg_wr_req.awprot)));
      if(w.wlast)begin
        rg_wr_state<= Idle;
        ff_sync_wr_resp.enq(b);
        `logLevel( ram2rw, 1, $format("RAM2RW : Burst WrResp: ", fshow (b)))
      end
    endrule:rl_wr_burst_req_to_device

    /*doc:rule: */
    rule rl_push_rd_axi4_resp;
      s_xactor.fifo_side.i_rd_data.enq(ff_sync_rd_resp.first);
      ff_sync_rd_resp.deq;
      `logLevel( dc2axi4, 0, $format("DC2AXI4: SyncResp:",fshow_axi4_rd_data(ff_sync_rd_resp.first)))
    endrule:rl_push_rd_axi4_resp

    /*doc:rule: */
    rule rl_push_wr_axi4_resp;
      s_xactor.fifo_side.i_wr_resp.enq(ff_sync_wr_resp.first);
      ff_sync_wr_resp.deq;
      `logLevel( dc2axi4, 0, $format("DC2AXI4: SyncResp:",fshow_axi4_wr_resp(ff_sync_wr_resp.first)))
    endrule:rl_push_wr_axi4_resp
  end
  else begin
    rule rl_rd_req_to_device(rg_rd_state == Idle);
      let req <- pop_o(s_xactor.fifo_side.o_rd_addr);
      if(req.arlen != 0)
        rg_rd_state <= Burst;
      rg_readreq_count <= req.arlen;
	  rg_rd_req <= req;
      `logLevel( dc2axi4, 1, $format("DC2AXI4: RdReq:", fshow_axi4_rd_addr(req)))
      let {succ, rdata}<- device_dcbus.read(req.araddr - fromInteger(base), unpack(truncate(req.arsize)),
                                            prot_ncode(truncate(req.arprot)));
      let lv_resp= Axi4_rd_data {rresp: succ? axi4_resp_okay : axi4_resp_slverr, rlast: req.arlen==0, rid: req.arid,
                                  rdata: rdata, ruser: req.aruser};
      `logLevel( dc2axi4, 1, $format("DC2AXI4: Read Resp:", fshow_axi4_rd_data(lv_resp)))
      s_xactor.fifo_side.i_rd_data.enq(lv_resp);
    endrule:rl_rd_req_to_device

    /*doc:rule: */
    rule rl_rd_burst_request(rg_rd_state == Burst);
  	  if(rg_readreq_count == 1)
  	    rg_rd_state <= Idle;

  	  let address=fn_axi4burst_addr(rg_rd_req.arlen,   rg_rd_req.arsize,
                                    rg_rd_req.arburst, rg_rd_req.araddr);
      rg_rd_req.araddr <= address;
      let {succ, rdata}<- device_dcbus.read(rg_rd_req.araddr - fromInteger(base), unpack(truncate(rg_rd_req.arsize)),
                                            prot_ncode(truncate(rg_rd_req.arprot)));
      rg_readreq_count <= rg_readreq_count - 1;
      let lv_resp= Axi4_rd_data {rresp: succ? axi4_resp_okay : axi4_resp_slverr, rlast: rg_readreq_count==1, rid:
        rg_rd_req.arid, rdata: rdata, ruser: rg_rd_req.aruser};
      `logLevel( dc2axi4, 1, $format("DC2AXI4: Burst Read Resp:", fshow_axi4_rd_data(lv_resp)))
      s_xactor.fifo_side.i_rd_data.enq(lv_resp);
    endrule:rl_rd_burst_request

    /*doc:rule: */
    rule rl_wr_req_to_device(rg_wr_state == Idle);
      let req <- pop_o(s_xactor.fifo_side.o_wr_addr);
      let reqd <- pop_o(s_xactor.fifo_side.o_wr_data);
      `logLevel( dc2axi4, 1, $format("DC2AXI4: WrReq:", fshow_axi4_wr_addr(req)))
      `logLevel( dc2axi4, 1, $format("DC2AXI4: WrDReq:", fshow_axi4_wr_data(reqd)))
      let succ<- device_dcbus.write(req.awaddr - fromInteger(base), reqd.wdata, reqd.wstrb,
                                    prot_ncode(truncate(req.awprot)));
      let lv_resp= Axi4_wr_resp {bresp: succ? axi4_resp_okay : axi4_resp_slverr, bid: req.awid,
                                  buser: req.awuser};
      `logLevel( dc2axi4, 1, $format("DC2AXI4: Write Resp:", fshow_axi4_wr_resp(lv_resp)))
      rg_write_response <= lv_resp;
      if(!reqd.wlast)
        rg_wr_state <= Burst;
      else
        s_xactor.fifo_side.i_wr_resp.enq(lv_resp);
      rg_wr_req <= req;
    endrule:rl_wr_req_to_device

    rule rl_wr_burst_req_to_device(rg_wr_state==Burst);
      let w <- pop_o(s_xactor.fifo_side.o_wr_data);
  	  let address=fn_axi4burst_addr(rg_wr_req.awlen,   rg_wr_req.awsize,
                                    rg_wr_req.awburst, rg_wr_req.awaddr);
      `logLevel( dc2axi4, 1, $format("DC2AXI4: Burst WrDReq:", fshow_axi4_wr_data(w)))
      rg_wr_req.awaddr <= address;
      let b = rg_write_response;
      b.buser = w.wuser;
      let succ<- device_dcbus.write(rg_wr_req.awaddr - fromInteger(base), w.wdata, w.wstrb,
                                    prot_ncode(truncate(rg_wr_req.awprot)));
      if(w.wlast)begin
        rg_wr_state<= Idle;
        s_xactor.fifo_side.i_wr_resp.enq(b);
        `logLevel( ram2rw, 1, $format("RAM2RW : Burst WrResp: ", fshow (b)))
      end
    endrule:rl_wr_burst_req_to_device
  end
  interface slave= s_xactor.axi4_side;
  interface device= lv_device_io;

endmodule:dc2axi4

endpackage: DCBus

