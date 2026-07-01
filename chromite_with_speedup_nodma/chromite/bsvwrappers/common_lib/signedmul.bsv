// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details 

package signedmul;

  interface Ifc_signedmul#(numeric type awidth, numeric type bwidth);
  	(*always_ready , always_enabled*)
  	method Action ia (Bit#(awidth) a);
  	(*always_ready , always_enabled*)
  	method Action ib (Bit#(bwidth) b);
  	(*always_enabled*)
  	method Bit#(TAdd#(awidth,bwidth)) oc ();
  endinterface
  
  import "BVI" signedmul=
  module mksignedmul(Ifc_signedmul#(awidth, bwidth));
  
  	parameter AWIDTH = valueOf(awidth);
  	parameter BWIDTH = valueOf(bwidth);
  
  	default_clock clk();
  	default_reset rstn();
  
  	method ia (a /*AWIDTH-1:0*/)
  		 enable((*inhigh*)ia_enable) ;
  	method ib (b /*BWIDTH-1:0*/)
  		 enable((*inhigh*)ib_enable) ;
  	method c /* AWIDTH + BWIDTH -1  :  0 */ oc ();
  
  	path (a, c);
  	path (b, c);

    schedule oc CF oc;
    schedule ia CF ib;
    schedule ia CF oc;
    schedule oc CF ib;
    schedule ia CF ia;
    schedule ib CF ib;
  
  endmodule

endpackage
