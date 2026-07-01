// see LICENSE.incore for more details on licensing terms
/*
Author: Arjun Menon, arjun@incoresemi.com
Description:  A modified version of the bluespec CBus where read and writes return success.
              Also, support for various write sizes have been added.
*/
package CBus;

////////////////////////////////////////////////////////////////////////////////
///
////////////////////////////////////////////////////////////////////////////////

`ifdef async_reset
  import RegOverrides  :: *;
`endif
import Clocks::*;
import List::*;
import ModuleCollect::*;
import RegFile::*;
import Vector::*;
import BUtils::*;

////////////////////////////////////////////////////////////////////////////////
///
////////////////////////////////////////////////////////////////////////////////

// Interface for the configuration bus ("back door" interface)
interface CBus#(type sa, type sd);
  method ActionValue#(Bool) write(Bit#(sa) addr, Bit#(sd) data, Bit#(TDiv#(sd,8)) strobe);
  (* always_ready *) 
  method ActionValue#(Tuple2#(Bit#(sd), Bool)) read(Bit#(sa) addr);
endinterface

// Interface coupling the CBus interface with the "front door" device interface
interface IWithCBus#(type cbus_IFC, type device_IFC);
  interface cbus_IFC cbus_ifc;
  interface device_IFC device_ifc;
endinterface

////////////////////////////////////////////////////////////////////////////////
///
////////////////////////////////////////////////////////////////////////////////

// Define CBusItem, the type of item to be collected by module collect
typedef CBus#(sa, sd) CBusItem #(type sa, type sd);

// Define ModWithCBus, the type of a module collecting CBusItems
typedef ModuleCollect#(CBusItem#(sa, sd), i) ModWithCBus#(type sa, type sd, type i);

typedef struct {
  Bit#(sa) a;
  Bit#(TLog#(sd)) o;
} CRAddr#(numeric type sa,numeric type sd) deriving(Bits, Eq);


instance Arith#( CRAddr#(t,d) )provisos(Arith#(Bit#(t))) ;

   function CRAddr#(t,d) \+ (CRAddr#(t,d) a0, CRAddr#(t,d) a1 );
     return CRAddr{ a: (a0.a + a1.a) ,
                    o: (a0.o + a1.o ) } ;
   endfunction

   function CRAddr#(t,d) \- (CRAddr#(t,d) a0, CRAddr#(t,d) a1 );
     return CRAddr{ a: (a0.a - a1.a) ,
                    o: (a0.o - a1.o ) } ;
   endfunction

   function CRAddr#(t,d) \* (CRAddr#(t,d) a0, CRAddr#(t,d) a1 );
     return error ("The operator " + quote("*") +
                   " is not defined for " + quote("CRAddr") + ".");
   endfunction

   function CRAddr#(t,d) negate ( CRAddr#(t,d) a0 );
     return CRAddr{ a: - a0.a , o: - a0.o } ;
   endfunction

   function CRAddr#(t,d) \/ (CRAddr#(t,d) a0, CRAddr#(t,d) a1 );
     return error ("The operator " + quote("/") +
                   " is not defined for " + quote("CRAddr") + ".");
   endfunction

   function CRAddr#(t,d) \% (CRAddr#(t,d) a0, CRAddr#(t,d) a1 );
     return error ("The operator " + quote("%") +
                   " is not defined for " + quote("CRAddr") + ".");
   endfunction

endinstance

instance Literal#(CRAddr#(t,d))
  provisos(Literal#(Bit#(t)));

  function fromInteger(n) ;
    return CRAddr{ a: fromInteger(n), o: 0 } ;
  endfunction
  function inLiteralRange(a, i);
    return inLiteralRange(a.a, i);
  endfunction
endinstance

////////////////////////////////////////////////////////////////////////////////
///
////////////////////////////////////////////////////////////////////////////////

// A module wrapper that adds the CBus to the collection and
// returns only the "front door" interface.
module [ModWithCBus#(sa, sd)] collectCBusIFC#(Module#(IWithCBus#(CBus#(sa, sd), i)) m)(i);
  IWithCBus#(CBus#(sa, sd), i) double_ifc();
  liftModule#(m) _temp(double_ifc);

  addToCollection(double_ifc.cbus_ifc);
  return(double_ifc.device_ifc);
endmodule

////////////////////////////////////////////////////////////////////////////////
///
////////////////////////////////////////////////////////////////////////////////

// A module wrapper that takes a module with a normal interface,
// processes the collected CBusItems and provides an IWithCBus interface.
module [Module] exposeCBusIFC#(ModWithCBus#(sa, sd, i) sm) (IWithCBus#(CBus#(sa, sd), i));

  IWithCollection#(CBusItem#(sa, sd), i) collection_ifc();
  exposeCollection#(sm) _temp(collection_ifc);

  Reg#(Bool) dummy <- mkReg(False);
  List#(CBus#(sa, sd)) item_list = collection_ifc.collection;

  interface CBus cbus_ifc;
    method ActionValue#(Bool) write(Bit#(sa) addr, Bit#(sd) data, Bit#(TDiv#(sd,8)) strobe);

      function ActionValue#(Bool) ifc_write(CBus#(sa, sd) item_ifc);
        actionvalue
          let value <- item_ifc.write(addr, data, strobe);
          return value;
         endactionvalue
      endfunction

      //joinActions(map(ifc_write, item_list));
      let vs <- List::mapM(ifc_write, item_list);
      return(foldt(bool_or, False, vs));
    endmethod

    method ActionValue#(Tuple2#(Bit#(sd), Bool)) read(Bit#(sa) addr);

      dummy <= !dummy;

      function ActionValue#(Tuple2#(Bit#(sd), Bool)) ifc_read(CBus#(sa, sd) item_ifc);
        actionvalue
          let value <- item_ifc.read(addr);
          return value;
        endactionvalue
      endfunction

      /// fold together the read values for all the collected interfaces
      let vs <- List::mapM(ifc_read, item_list);
      return(foldt(tuple2_or, tuple2(0, False), vs));
    endmethod

  endinterface
  interface device_ifc = collection_ifc.device;
endmodule



////////////////////////////////////////////////////////////////////////////////
///
////////////////////////////////////////////////////////////////////////////////

function d fn_compute_write_data(d old_data, d new_data, a addr, o offset, s strobe)
provisos(Bits#(d,sd), Bits#(a,sa), Bits#(o,so), Bits#(s,ss), Bitwise#(d), Bitwise#(s), Bitwise#(o),
         PrimShiftIndex#(o,a__),Div#(sd,8,ss), Mul#(TDiv#(sd, 8), 8, sd));
  let v_addrbits= valueOf(sa);
  strobe= strobe >> (offset>>v_addrbits);
  Vector#(TDiv#(sd,8), Bit#(1)) vec_strobe= unpack(pack(strobe));
  Vector#(TDiv#(sd,8), Bit#(8)) vec_mask= map(duplicate, vec_strobe);
  d mask= unpack(pack(vec_mask));
  d res= ((new_data>>offset) & mask) | (old_data & ~mask);
  return res;
endfunction

// One basic configuration register with RW capabilities.
module regRW#(Bit#(sa) reg_addr, Bit#(TLog#(sd)) offset, r reset)
(IWithCBus#(CBus#(sa, sd), Reg#(r)))
provisos (Bits#(r, sr), Mul#(TDiv#(sd, 8), 8, sd), Add#(a__, sr, sd));

  Reg#(r) x <- mkReg(reset);
  //mkReg#(reset) inner_reg(x);

  PulseWire written <- mkPulseWire;

  interface CBus cbus_ifc;

    method ActionValue#(Bool) write(Bit#(sa) addr, Bit#(sd) data, Bit#(TDiv#(sd,8)) strobe);
      if (addr == reg_addr)
      begin
        Bit#(sd) x1= zeroExtend(pack(x));
        let shifted = fn_compute_write_data(x1, data, addr, offset, strobe);
        x <= unpack(truncateNP(shifted));
        written.send; // give cbus write priority over device _write.
        return True;
      end
      else
        return False;
    endmethod

    method ActionValue#(Tuple2#(Bit#(sd), Bool)) read(Bit#(sa) addr);
      if (addr == reg_addr)
      begin
        let shifted = zeroExtendNP(pack(x)) << offset;
        return tuple2(shifted, True);
      end
      else
        return tuple2(0, False);
    endmethod

  endinterface

  interface Reg device_ifc;
    method Action _write (value);
      if (!written) x <= value;
    endmethod

    method _read = x._read;
  endinterface

endmodule

// A wrapper to provide just a normal Reg interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal register would be used).
module [ModWithCBus#(sa, sd)] mkCBRegRW#(CRAddr#(sa2,sd) addr, r x)(Reg#(r))
provisos (Bits#(r, sr), Add#(ignore, sa2, sa), Mul#(TDiv#(sd, 8), 8, sd), Add#(a__, sr, sd));
  Bit#(sa)        reg_addr = {0, addr.a};
  Bit#(TLog#(sd)) reg_offset = {0, addr.o};
  let ifc();
  collectCBusIFC#(regRW(reg_addr, reg_offset, x)) _temp(ifc);
  return(ifc);
endmodule

//////////////////////////////////////////////////////////////////////
///
//////////////////////////////////////////////////////////////////////

module regR#(Bit#(sa) reg_addr, Bit#(TLog#(sd)) offset, r reset)(IWithCBus#(CBus#(sa, sd), Reg#(r)))
provisos (Bits#(r, sr));

  Reg#(r) x <- mkReg(reset);

  interface CBus cbus_ifc;
    method ActionValue#(Bool) write(Bit#(sa) addr, Bit#(sd) data, Bit#(TDiv#(sd,8)) strobe);
      if (addr == reg_addr)
        $display("Warning: attempt to write to a read only config bus at offset %x at time ", offset, $time);
      return False;
    endmethod

    method ActionValue#(Tuple2#(Bit#(sd), Bool)) read(Bit#(sa) addr);
      if (addr == reg_addr)
      begin
        let shifted = zeroExtendNP(pack(x)) << offset;
        return tuple2(shifted, True);
      end
      else
        return tuple2(0, False);
    endmethod

  endinterface

  interface Reg device_ifc;
    method Action _write (value);
      x <= value;
    endmethod

    method _read = x._read;
  endinterface

endmodule

module [ModWithCBus#(sa, sd)] mkCBRegR#(CRAddr#(sa2,sd) addr, r x)(Reg#(r))
  provisos (Bits#(r, sr), Add#(ignore, sa2, sa));
  Bit#(sa)        reg_addr   = {0, addr.a};
  Bit#(TLog#(sd)) reg_offset = {0, addr.o};
  let ifc();
  collectCBusIFC#(regR(reg_addr, reg_offset, x)) _temp(ifc);
  return(ifc);
endmodule

//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////
// One basic configuration register with RW capabilities.
module regW#(Bit#(sa) reg_addr, Bit#(TLog#(sd)) offset, r reset)(IWithCBus#(CBus#(sa, sd), Reg#(r)))
provisos (Bits#(r, sr), Mul#(TDiv#(sd, 8), 8, sd), Add#(a__, sr, sd));

  Reg#(r) x <-  mkReg(reset);
  PulseWire written <- mkPulseWire;

  interface CBus cbus_ifc;

    method ActionValue#(Bool) write(Bit#(sa) addr, Bit#(sd) data, Bit#(TDiv#(sd,8)) strobe);
      if (addr == reg_addr)
      begin
        Bit#(sd) x1= zeroExtend(pack(x));
        let shifted = fn_compute_write_data(x1, data, addr, offset, strobe);
        x <= unpack(truncateNP(shifted));
        written.send; // give cbus write priority over device _write.
        return True;
      end
      else 
        return False;
    endmethod

    method ActionValue#(Tuple2#(Bit#(sd), Bool)) read(Bit#(sa) addr);
      if (addr == reg_addr)
        $display("Warning: attempt to read a write only config bus at offset %x at time ", offset, $time);
      return tuple2(0, False);
    endmethod

  endinterface

  interface Reg device_ifc;
    method Action _write (value);
      if (!written) x <= value;
    endmethod

    method _read = x._read;
  endinterface

endmodule

// A wrapper to provide just a normal Reg interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal register would be used).
module [ModWithCBus#(sa, sd)] mkCBRegW#(CRAddr#(sa2,sd) addr, r x)(Reg#(r))
  provisos (Bits#(r, sr), Add#(ignore, sa2, sa), Mul#(TDiv#(sd, 8), 8, sd), Add#(a__, sr, sd));
  Bit#(sa)        reg_addr   = {0, addr.a};
  Bit#(TLog#(sd)) reg_offset = {0, addr.o};
  let ifc();
  collectCBusIFC#(regW(reg_addr, reg_offset, x)) _temp(ifc);
  return(ifc);
endmodule

////////////////////////////////////////////////////////////////////////////////
module regRC#(Bit#(sa) reg_addr, Bit#(TLog#(sd)) offset, r reset)(IWithCBus#(CBus#(sa, sd), Reg#(r)))
provisos (Bits#(r, sr), Add#(k, sr, sd), Mul#(TDiv#(sd, 8), 8, sd), Add#(a__, sr, sd));

  Reg#(r) x <- mkReg(reset);
  PulseWire written <- mkPulseWire;

  interface CBus cbus_ifc;
    method ActionValue#(Bool) write(Bit#(sa) addr, Bit#(sd) data, Bit#(TDiv#(sd,8)) strobe);
      if (addr == reg_addr) begin

        // data written as 0 does nothing
        // data written as 1 clears the related bit
        Bit#(sd) x1= zeroExtend(pack(x));
        let shifted = fn_compute_write_data(x1, data, addr, offset, strobe);
        Bit#(sr) mask = truncate(~shifted);
        Bit#(sr) res  = pack(x) & mask;
        x <= unpack(res);

        written.send; // give cbus write priority over device _write.
        return True;
      end
      else
        return False;
    endmethod

    method ActionValue#(Tuple2#(Bit#(sd), Bool)) read(Bit#(sa) addr);
      if (addr == reg_addr) begin
        let shifted = {0, pack(x)} << offset;
        return tuple2(shifted, True);
      end
      else
        return tuple2(0, False);
    endmethod
  endinterface

  interface Reg device_ifc;
    method Action _write (value);
      if (!written) x <= value;
    endmethod

    method _read = x._read;
  endinterface

endmodule

module [ModWithCBus#(sa, sd)] mkCBRegRC#(CRAddr#(sa2,sd) addr, r x)(Reg#(r))
provisos (Bits#(r, sr), Add#(k, sr, sd), Add#(ignore, sa2, sa), Mul#(TDiv#(sd, 8), 8, sd),
          Add#(a__, sr, sd));
  Bit#(sa)        reg_addr   = {0, addr.a};
  Bit#(TLog#(sd)) reg_offset = {0, addr.o};
  let ifc();
  collectCBusIFC#(regRC(reg_addr, reg_offset, x)) _temp(ifc);
  return(ifc);
endmodule

////////////////////////////////////////////////////////////////////////////////
///
////////////////////////////////////////////////////////////////////////////////

module regFile#(Bit#(sa) reg_addr, Bit#(sa) size)(IWithCBus#(CBus#(sa, sd), RegFile#(Bit#(sa), r)))
provisos (Bits#(r, sr), Add#(k, sr, sd), Mul#(TDiv#(sd, 8), 8, sd));

  let min = reg_addr;
  let max = reg_addr + (size - 1);

  RegFile#(Bit#(sa), r) mem <- mkRegFile(min, max);

  interface CBus cbus_ifc;

    method ActionValue#(Bool) write(Bit#(sa) addr, Bit#(sd) data, Bit#(TDiv#(sd,8)) strobe);
    if ((addr >= min) && (addr <= max))
    begin
      //Bit#(sd) shifted = fn_compute_write_data(data, data, addr, 0, '1); //Change to mem.sub
      let value = unpack(truncate(data));
      mem.upd(addr, value);
      return True;
    end
    else
      return False;
    endmethod

    method ActionValue#(Tuple2#(Bit#(sd), Bool)) read(Bit#(sa) addr);
      if ((addr >= min) && (addr <= max))
      begin
        let value = mem.sub(addr);
        return tuple2({0, pack(value)}, True);
      end
      else
        return tuple2(0, False);
    endmethod

  endinterface

  interface RegFile device_ifc = mem;

endmodule

// A wrapper to provide just a normal RegFile interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal RegFile would be used).
module [ModWithCBus#(sa, sd)] mkCBRegFile#(Bit#(sa) reg_addr, Bit#(sa) size)(RegFile#(Bit#(sa), r))
  provisos (Bits#(r, sr), Add#(k, sr, sd), Mul#(TDiv#(sd, 8), 8, sd));
  let ifc();
  collectCBusIFC#(regFile(reg_addr, size)) _temp(ifc);
  return(ifc);
endmodule

////////////////////////////////////////////////////////////////////////////////
/// Some support functions
////////////////////////////////////////////////////////////////////////////////

// A variant of a BSV library definition: takes an extra parameter, to
// be used in the (previously disallowed) case where the list argument
// is Nil:

function a foldt(function a f(a x1, a x2), a x, List#(a) xs);
  case (xs) matches
    tagged Nil: return (x);
    default   : return (List::fold(f, xs));
  endcase
endfunction

function Bit#(n) bit_or (Bit#(n) x,  Bit#(n) y);
  return (x | y);
endfunction

function Tuple2#(Bit#(n), Bool) tuple2_or (Tuple2#(Bit#(n), Bool) x, Tuple2#(Bit#(n), Bool) y);
  Bit#(n) lv1 = tpl_1(x) | tpl_1(y);
  Bool    lv2 = tpl_2(x) || tpl_2(y);
  return tuple2(lv1, lv2);
endfunction

function Bool bool_or (Bool x, Bool y);
  return (x || y);
endfunction

// The function to fold together maybe values. When both are valid, use
// "or" (it shouldn't happen).
function Maybe#(Bit#(n)) fold_maybes ( Maybe#(Bit#(n)) x,  Maybe#(Bit#(n)) y);
  if (!isValid(x) && !isValid(y))
    return Invalid;
  else
    return Valid(fromMaybe(0,x) | fromMaybe(0,y));
endfunction

function a grab_left(b value) provisos(Bits#(a, sa), Bits#(b, sb), Add#(x, sa, sb));
  let result = truncate(pack(value) >> fromInteger((valueOf(sb) - valueOf(sa))));
  return unpack(result);
endfunction

////////////////////////////////////////////////////////////////////////////////
///
////////////////////////////////////////////////////////////////////////////////


typeclass ExtendNP#(type a, numeric type m, numeric type n ) ;
  function a#(m) extendNP(a#(n) x);
  function a#(m) zeroExtendNP(a#(n) x);
  function a#(m) signExtendNP(a#(n) x);
  function a#(m) truncateNP(a#(n) x);
  function a#(m) truncateLSBNP(a#(n) x);
endtypeclass

instance ExtendNP#( Bit, m, n );
  function Bit#(m) extendNP( Bit#(n) b)      = zeroExtendNPBits (b);
  function Bit#(m) zeroExtendNP( Bit#(n) b)  = zeroExtendNPBits (b);
  function Bit#(m) signExtendNP( Bit#(n) b)  = signExtendNPBits (b);
  function Bit#(m) truncateNP( Bit#(n) b)    = truncateNPBits (b);
  function Bit#(m) truncateLSBNP( Bit#(n) b) = truncateLSBNPBits (b);   
endinstance


instance ExtendNP#( Int, m, n );
  function Int#(m) extendNP( Int#(n) b)      = unpack (signExtendNPBits (pack(b)));
  function Int#(m) zeroExtendNP( Int#(n) b)  = unpack (zeroExtendNPBits (pack(b)));
  function Int#(m) signExtendNP( Int#(n) b)  = unpack (signExtendNPBits (pack(b)));
  function Int#(m) truncateNP( Int#(n) b)    = unpack (truncateNPBits (pack(b)));
  function Int#(m) truncateLSBNP( Int#(n) b) = unpack (truncateLSBNPBits (pack(b)));   
endinstance

instance ExtendNP#( UInt, m, n );
  function UInt#(m) extendNP( UInt#(n) b)      = unpack (zeroExtendNPBits (pack(b)));
  function UInt#(m) zeroExtendNP( UInt#(n) b)  = unpack (zeroExtendNPBits (pack(b)));
  function UInt#(m) signExtendNP( UInt#(n) b)  = unpack (signExtendNPBits (pack(b)));
  function UInt#(m) truncateNP( UInt#(n) b)    = unpack (truncateNPBits (pack(b)));
  function UInt#(m) truncateLSBNP( UInt#(n) b) = unpack (truncateLSBNPBits (pack(b)));   
endinstance

function Bit#(m) zeroExtendNPBits (Bit#(n) din) provisos( Add#(m,n,mn) );
  let mi = valueOf(m);
  let ni = valueOf(n);
  let err = error ("incorrect zeroExtendNP from " + integerToString(ni) +
                   " to " + integerToString(mi) + ".");
  Bit#(mn) x = zeroExtend(din);
  return (mi < ni) ? err : truncate(x);
endfunction

function Bit#(m) signExtendNPBits (Bit#(n) din)
  provisos( Add#(m,n,mn) );
  let mi = valueOf(m);
  let ni = valueOf(n);
  let err = error ("incorrect signExtendNP from " + integerToString(ni) +
                   " to " + integerToString(mi) + ".");
  Bit#(mn) x = signExtend(din);
  return (mi < ni) ? err: truncate(x);
endfunction

function Bit#(m) truncateNPBits (Bit#(n) din)
  provisos( Add#(m,n,mn) );
  let mi = valueOf(m);
  let ni = valueOf(n);
  let err = error ("incorrect truncateNP from " + integerToString(ni) +
                   " to " + integerToString(mi) + ".");
  Bit#(mn) x = zeroExtend(din);
  return (mi > ni) ? err : truncate(x);
endfunction

function Bit#(m) truncateLSBNPBits (Bit#(n) din);
  let mi = valueOf(m);
  let ni = valueOf(n);
  let err = error ("incorrect truncateLSBNP from " + integerToString(ni) +
                   " to " + integerToString(mi) + ".");
  let x = pack(din) >> fromInteger((ni - mi));
  return (mi > ni) ? err : truncateNP(x);
endfunction

endpackage
