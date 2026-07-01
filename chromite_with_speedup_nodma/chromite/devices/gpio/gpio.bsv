// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Thursday 23 April 2020 05:30:48 PM IST

*/
package gpio;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import Vector       :: * ;
import Reserved     :: * ;

`include "Logger.bsv"
import apb          :: * ;
import axi4l        :: * ;
//import axi4          :: * ;
import DCBus        :: * ;

typedef DCRAddr#(7, 2) MMRA; // Memory mapped registre attributes
typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw), Ifc_gpio#(ionum,interrupt_size))
    Ifc_gpio_axi4l#(type aw, type dw, type uw, numeric type ionum, numeric type interrupt_size);
typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Ifc_gpio#(ionum, interrupt_size))
    Ifc_gpio_apb#(type aw, type dw, type uw, numeric type ionum, numeric type interrupt_size);
/*typedef IWithSlave#(Ifc_axi4_slave#(iw, aw, dw, uw), Ifc_gpio_sb#(ionum, interrupt_size))
    Ifc_gpio_axi4#(type iw, type aw, type dw, type uw, numeric type ionum, numeric type interrupt_size);*/

function Bit#(n) vec2bits (Vector#(n, Bit#(1)) a);
  let v_n = valueOf(n);
  Bit#(n) _t;
  for (Integer i = 0; i<v_n; i = i + 1) begin
    _t[i] = a[i];
  end
  return _t;
endfunction:vec2bits

function Vector#(n,Bit#(1)) bits2vec (Bit#(n) a);
  let v_n = valueOf(n);
  Vector#(n,Bit#(1)) _t;
  for (Integer i = 0; i<v_n; i = i + 1) begin
    _t[i] = a[i];
  end
  return _t;
endfunction:bits2vec

module regCustomRW#(DCRAddr#(aw,o) attr, r reset, Reg#(r) s)(IWithDCBus#(DCBus#(aw, dw), Reg#(r)))
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
      Bit#(TSub#(aw,3)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,3)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
      if ((req_index == reg_index) && perm) begin
        let {succ, temp} <- fn_adjust_write(addr, data, strobe, pack(x), attr.min, attr.max, attr.mask);
        if(succ) begin s<= unpack(pack(s)&~temp); end // give cbus write priority over device _write.
        return succ;
      end
      else
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(TSub#(aw,3)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,3)) reg_index = truncateLSB(attr.addr);
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
  endinterface:device
endmodule:regCustomRW

// A wrapper to provide just a normal Reg interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal register would be used).
module [ModWithDCBus#(aw, dw)] mkDCBRegCustomRW#(DCRAddr#(aw,o) attr, r x, Reg#(r) s)(Reg#(r))
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
  collectDCBusIFC#(regCustomRW(attr, x, s)) _temp(ifc);
  return(ifc);
endmodule:mkDCBRegCustomRW

(*always_ready,always_enabled*)
interface GPIO# (numeric type ionum);
  (*prefix=""*)
	method Action gpio_in_val ( (*port="gpio_in_val"*) Vector#(ionum, Bit#(1)) in);
	method Vector#(ionum,Bit#(1))   gpio_in_en;
	method Vector#(ionum,Bit#(1))   gpio_out_val;
	method Vector#(ionum,Bit#(1))   gpio_out_en;
	method Vector#(ionum,Bit#(1))   gpio_pullup_en;
	method Vector#(ionum,Bit#(1))   gpio_drive_0;
	method Vector#(ionum,Bit#(1))   gpio_drive_1;
	method Vector#(ionum,Bit#(1))   gpio_drive_2;
endinterface:GPIO

interface Ifc_gpio#( numeric type ionum, numeric type interrupt_size);
  (*prefix=""*)
  interface GPIO#(ionum) io;
  method Bit#(interrupt_size) sb_gpio_to_plic;
endinterface:Ifc_gpio

typedef struct{
  ReservedZero#(TSub#(32,ionum)) zeros;
  Bit#(ionum) val;
}GpioVal #(numeric type ionum) deriving(Bits, Eq, FShow);

module [ModWithDCBus#(aw,dw)] mk_gpio (Ifc_gpio#(ionum, interrupt_size))
  provisos(
    Add#(16, _a, aw),
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(dw, _c, 32), // not more than 32 gpios per block
    Add#(interrupt_size,_d,ionum), //interrupt connected to plic should be less than ionum

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8),
    Mul#(TDiv#(TAdd#(TSub#(32, ionum), ionum), 8), 8, TAdd#(TSub#(32, ionum),
    ionum))
  );

  let v_dw = valueOf(dw);

   DCRAddr#(aw,2) attr_input_val  = DCRAddr{addr:'h0 ,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_input_en   = DCRAddr{addr:'h4 ,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_output_val = DCRAddr{addr:'h8 ,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_output_en  = DCRAddr{addr:'hc ,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_pullup_en  = DCRAddr{addr:'h10,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_drive_0    = DCRAddr{addr:'h14,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_rise_ie    = DCRAddr{addr:'h18,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_rise_ip    = DCRAddr{addr:'h1c,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_fall_ie    = DCRAddr{addr:'h20,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_fall_ip    = DCRAddr{addr:'h24,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_high_ie    = DCRAddr{addr:'h28,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_high_ip    = DCRAddr{addr:'h2c,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_low_ie     = DCRAddr{addr:'h30,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_low_ip     = DCRAddr{addr:'h34,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_set_out    = DCRAddr{addr:'h38,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_clr_out    = DCRAddr{addr:'h3c,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_xor_out    = DCRAddr{addr:'h40,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_drive_1    = DCRAddr{addr:'h44,min:Sz1,max:Sz4,mask:2'b11};
   DCRAddr#(aw,2) attr_drive_2    = DCRAddr{addr:'h48,min:Sz1,max:Sz4,mask:2'b11};

  Reg#(GpioVal#(ionum))  rg_in_sync1 <- mkReg(unpack(0));
  Reg#(GpioVal#(ionum))  rg_in_sync2 <- mkReg(unpack(0));
  Reg#(GpioVal#(ionum))  rg_in_sync3 <- mkReg(unpack(0));
  Reg#(GpioVal#(ionum))  rg_interrupt <- mkReg(unpack(0));
  Wire#(GpioVal#(ionum)) wr_clear_interrupt <- mkWire();


  Reg#(GpioVal#(ionum))  rg_input_val  <- mkDCBRegRO(attr_input_val,unpack(0));
  Reg#(GpioVal#(ionum))  rg_input_en   <- mkDCBRegRW(attr_input_en ,unpack(0));
  Reg#(GpioVal#(ionum))  rg_output_val <- mkDCBRegRW(attr_output_val ,unpack(0));
  Reg#(GpioVal#(ionum))  rg_output_en  <- mkDCBRegRW(attr_output_en ,unpack(0));
  Reg#(GpioVal#(ionum))  rg_pullup_en  <- mkDCBRegRW(attr_pullup_en, unpack(0));
  Reg#(GpioVal#(ionum))  rg_drive_0    <- mkDCBRegRW(attr_drive_0, unpack(0));
  Reg#(GpioVal#(ionum))  rg_drive_1    <- mkDCBRegRW(attr_drive_1, unpack(0));
  Reg#(GpioVal#(ionum))  rg_drive_2    <- mkDCBRegRW(attr_drive_2, unpack(0));
  Reg#(GpioVal#(ionum))  rg_rise_ip    <- mkDCBRegCustomRW(attr_rise_ip, unpack(0), rg_interrupt);
  Reg#(GpioVal#(ionum))  rg_rise_ie    <- mkDCBRegRW(attr_rise_ie, unpack(0));
  Reg#(GpioVal#(ionum))  rg_fall_ip    <- mkDCBRegCustomRW(attr_fall_ip, unpack(0), rg_interrupt);
  Reg#(GpioVal#(ionum))  rg_fall_ie    <- mkDCBRegRW(attr_fall_ie, unpack(0));
  Reg#(GpioVal#(ionum))  rg_high_ip    <- mkDCBRegCustomRW(attr_high_ip, unpack(0), rg_interrupt);
  Reg#(GpioVal#(ionum))  rg_high_ie    <- mkDCBRegRW(attr_high_ie, unpack(0));
  Reg#(GpioVal#(ionum))  rg_low_ip     <- mkDCBRegCustomRW(attr_low_ip,  unpack(0), rg_interrupt);
  Reg#(GpioVal#(ionum))  rg_low_ie     <- mkDCBRegRW(attr_low_ie,  unpack(0));
  Reg#(GpioVal#(ionum))  rg_xor_out    <- mkDCBRegRW(attr_xor_out, unpack(0));
  Reg#(GpioVal#(ionum))  rg_set_out    <- mkDCBRegRW(attr_set_out, unpack(0));
  Reg#(GpioVal#(ionum))  rg_clr_out    <- mkDCBRegRW(attr_clr_out, unpack(0));

  /*[>doc:rule: <]
  rule rl_show_regs;
    `logLevel( gpio, 2, $format("GPIO: rg_rise_ip:%h",rg_rise_ip))
    `logLevel( gpio, 2, $format("GPIO: rg_rise_ie:%h",rg_rise_ie))
    `logLevel( gpio, 2, $format("GPIO: rg_fall_ip:%h",rg_fall_ip))
    `logLevel( gpio, 2, $format("GPIO: rg_fall_ie:%h",rg_fall_ie))
    `logLevel( gpio, 2, $format("GPIO: rg_high_ip:%h",rg_high_ip))
    `logLevel( gpio, 2, $format("GPIO: rg_high_ie:%h",rg_high_ie))
    `logLevel( gpio, 2, $format("GPIO: rg_low_ip :%h",rg_low_ip ))
    `logLevel( gpio, 2, $format("GPIO: rg_low_ie :%h",rg_low_ie ))
  endrule*/

  /*doc:rule: */
  rule rl_sync_inval;
    rg_in_sync2.val <= rg_in_sync1.val;
    rg_in_sync3.val <= rg_in_sync2.val;
    rg_input_val.val <= rg_in_sync3.val;
  endrule:rl_sync_inval

  /*doc:rule: */
  rule rl_capture_all_interrupts;
    rg_high_ip.val  <= rg_high_ip.val ^ rg_input_val.val;
    rg_low_ip.val   <= rg_low_ip.val  ^ ~rg_input_val.val;
    let lv_rise      =  rg_in_sync2.val & ~rg_input_val.val;
    rg_rise_ip.val  <= rg_rise_ip.val ^ lv_rise;
    let lv_fall      = ~rg_in_sync2.val & rg_input_val.val;
    rg_fall_ip.val  <= rg_fall_ip.val ^ lv_fall;
  endrule:rl_capture_all_interrupts

  rule rl_generate_interrupt;
    let lv_high_irq = rg_high_ie.val & rg_high_ip.val;
    let lv_low_irq  = rg_low_ie.val  & rg_low_ip.val;
    let lv_rise_irq = rg_rise_ie.val & rg_rise_ip.val;
    let lv_fall_irq = rg_fall_ie.val & rg_fall_ip.val;
    rg_interrupt.val <= lv_high_irq | lv_low_irq | lv_rise_irq | lv_fall_irq | rg_interrupt.val;
  endrule:rl_generate_interrupt

  interface io = interface GPIO
	  method Action gpio_in_val (Vector#(ionum, Bit#(1)) in);
	    rg_in_sync1.val <= vec2bits(in);
	  endmethod
	  method gpio_in_en     = bits2vec(rg_input_en.val);
	  method gpio_out_val   = bits2vec(((rg_output_val.val&~rg_clr_out.val)|rg_set_out.val)^rg_xor_out.val);
	  method gpio_out_en    = bits2vec(rg_output_en.val);
	  method gpio_pullup_en = bits2vec(rg_pullup_en.val);
	  method gpio_drive_0   = bits2vec(rg_drive_0.val);
	  method gpio_drive_1   = bits2vec(rg_drive_1.val);
	  method gpio_drive_2   = bits2vec(rg_drive_2.val);
	endinterface;
	interface sb_gpio_to_plic = truncate(rg_interrupt.val);

endmodule:mk_gpio

module [Module] mk_gpio_block(IWithDCBus#(DCBus#(aw,dw), Ifc_gpio#(ionum,interrupt_size)))
	provisos(
    Add#(16, _a, aw),
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(dw, _c, 32), // not more than 32 gpios per block
    Add#(interrupt_size,_d,ionum), //interrupt connected to plic should be less than ionum


    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8),
    Mul#(TDiv#(TAdd#(TSub#(32, ionum), ionum), 8), 8, TAdd#(TSub#(32, ionum),
    ionum))

	);
  let ifc <- exposeDCBusIFC(mk_gpio);
  return ifc;
endmodule:mk_gpio_block
module [Module] mkgpio_axi4l#(parameter Integer base, Clock gpio_clk, Reset gpio_rst)
  (Ifc_gpio_axi4l#(aw, dw, uw, ionum,interrupt_size))
	provisos(
    Add#(16, _a, aw),
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(dw, _c, 32), // not more than 32 gpios per block
    Add#(interrupt_size,_d,ionum), //interrupt connected to plic should be less than ionum

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8),
    Mul#(TDiv#(TAdd#(TSub#(32, ionum), ionum), 8), 8, TAdd#(TSub#(32, ionum),
    ionum))
	);

  let gpio_mod = mk_gpio_block(clocked_by gpio_clk, reset_by gpio_rst);
  Ifc_gpio_axi4l#(aw, dw, uw, ionum,interrupt_size) gpio <-
      dc2axi4l(gpio_mod, base, gpio_clk, gpio_rst);
  return gpio;
endmodule:mkgpio_axi4l
module [Module] mkgpio_apb#(parameter Integer base,Clock gpio_clk, Reset gpio_rst)
  (Ifc_gpio_apb#(aw, dw, uw, ionum,interrupt_size))
	provisos(
    Add#(16, _a, aw),
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(dw, _c, 32), // not more than 32 gpios per block
    Add#(interrupt_size,_d,ionum), //interrupt connected to plic should be less than ionum

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8),
    Mul#(TDiv#(TAdd#(TSub#(32, ionum), ionum), 8), 8, TAdd#(TSub#(32, ionum),
    ionum))
	);

  let gpio_mod = mk_gpio_block(clocked_by gpio_clk, reset_by gpio_rst);
  Ifc_gpio_apb#(aw, dw, uw, ionum, interrupt_size) gpio <-
      dc2apb(gpio_mod, base, gpio_clk, gpio_rst);
  return gpio;
endmodule:mkgpio_apb
/*module [Module] mkgpio_axi4#(Clock gpio_clk, Reset gpio_rst)
  (Ifc_gpio_axi4#(iw, aw, dw, uw, ionum, interrupt_size))
	provisos(
    Add#(16, _a, aw),
    Add#(8, _b, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(dw, _c, 32), // not more than 32 gpios per block
    Add#(interrupt_size,_d,ionum), //interrupt connected to plic should be less than ionum

    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(d__, TDiv#(dw, 8), 8),
    Mul#(TDiv#(TAdd#(TSub#(32, ionum), ionum), 8), 8, TAdd#(TSub#(32, ionum),
    ionum))
	);

  let gpio_mod = mk_gpio_block(clocked_by gpio_clk, reset_by gpio_rst);
  Ifc_gpio_axi4#(iw, aw, dw, uw, ionum, interrupt_size)  gpio <-
      dc2axi4(gpio_mod, gpio_clk, gpio_rst);
  return gpio;
endmodule:mkgpio_axi4*/

endpackage:gpio

