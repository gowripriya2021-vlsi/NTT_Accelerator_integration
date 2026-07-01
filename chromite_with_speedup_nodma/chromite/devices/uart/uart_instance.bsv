// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details.
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Sunday 19 April 2020 08:47:50 PM IST

*/
package uart_instance;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;

`include "Logger.bsv"
import uart         :: * ;

(*synthesize*)
module mkinst_uartaxi4l(Ifc_uart_axi4l#(32, 32, 0, 16));
  let clk <- exposeCurrentClock;
  let reset <- exposeCurrentReset;
  let ifc();
  mkuart_axi4l#(5, 'h11300, clk, reset) _temp(ifc);
  return ifc;
endmodule:mkinst_uartaxi4l

/*(*synthesize*)
module mkinst_uartaxi4(Ifc_uart_axi4#(4, 32, 64, 0, 16));
	let clk <-exposeCurrentClock;
	let reset <-exposeCurrentReset;
  let ifc();
  mkuart_axi4#(5, 'h11300, clk, reset) _temp(ifc);
  return ifc;
endmodule:mkinst_uartaxi4*/

(*synthesize*)
module mkinst_uartapb(Ifc_uart_apb#(32, 32, 0, 16));
	let clk <-exposeCurrentClock;
	let reset <-exposeCurrentReset;
  let ifc();
  mkuart_apb#(5, 'h11300, clk, reset) _temp(ifc);
  return ifc;
endmodule:mkinst_uartapb

endpackage:uart_instance

