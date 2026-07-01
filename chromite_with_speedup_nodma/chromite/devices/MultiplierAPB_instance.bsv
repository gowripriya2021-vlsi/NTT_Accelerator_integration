// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details.
/*
Author: Your Name
Email: your.email@example.com
Created on: [Date]
*/
package multiplier_instance;
import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
`include "Logger.bsv"
import MultiplierAPB :: * ;

(*synthesize*)
module mkinst_multiplierapb(Ifc_multiplier_apb#(32, 32, 0));
  let clk <- exposeCurrentClock;
  let reset <- exposeCurrentReset;
  let ifc();
  mkmultiplier_apb#('h00011100, clk, reset) _temp(ifc);
  return ifc;
endmodule: mkinst_multiplierapb

endpackage: multiplier_instance