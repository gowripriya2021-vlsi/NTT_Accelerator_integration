// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 01 July 2020 03:21:25 PM

*/
package uart16550_instance;
import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import uart16550    :: * ;

`include "Logger.bsv"

(*synthesize*)
module mkinst_uart16550axi4l(Ifc_uart16550_axi4l#(32, 32, 0, 16));
  let clk <- exposeCurrentClock;
  let reset <- exposeCurrentReset;
  let ifc();
  mkuart16550_axi4l#('h11300, clk, reset) _temp(ifc);
  return ifc;
endmodule:mkinst_uart16550axi4l

(*synthesize*)
module mkinst_uart16550apb(Ifc_uart16550_apb#(32, 32, 0, 16));
	let clk <-exposeCurrentClock;
	let reset <-exposeCurrentReset;
  let ifc();
  mkuart16550_apb#('h11300, clk, reset) _temp(ifc);
  return ifc;
endmodule:mkinst_uart16550apb
endpackage:uart16550_instance

