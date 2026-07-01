// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Saturday 25 April 2020 08:45:12 PM IST

*/
package plic_instance ;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;

  `include "Logger.bsv"

  import plic         :: * ;
  import gateway      :: * ;
  import apb          :: * ;
  import axi4l        :: * ;

`define base 'h2000000

(*synthesize*)
module [Module] mkinst_gateway(Ifc_gateway2);
  let clk <- exposeCurrentClock;
  let rst <- exposeCurrentReset;
  let ifc();
  mk_gateway2#(1, clk, rst, 0, 1) _temp(ifc);
  return ifc;
endmodule:mkinst_gateway

(*synthesize*)
module [Module] mkinst_gateway2#(Clock src_clock, Reset src_reset)(Ifc_gateway2);
  let clk <- exposeCurrentClock;
  let rst <- exposeCurrentReset;
  let ifc();
  mk_gateway2#(1, src_clock, src_reset, 0, 1) _temp(ifc);
  return ifc;
endmodule:mkinst_gateway2

(*synthesize*)
module [Module] mkinst_plicapb(Ifc_plic_apb#(26, 32, 0, 16, 2, 7));
  let clk <- exposeCurrentClock;
  let rst <- exposeCurrentReset;
  let ifc();
  mkplic_apb#(`base, clk, rst) _temp(ifc);
  return ifc;
endmodule:mkinst_plicapb

(*synthesize*)
module [Module] mkinst_plicaxi4l(Ifc_plic_axi4l#(26, 64, 0, 64, 2, 3));
  let clk <- exposeCurrentClock;
  let rst <- exposeCurrentReset;
  let ifc();
  mkplic_axi4l#(`base, clk, rst) _temp(ifc);
  return ifc;
endmodule:mkinst_plicaxi4l
endpackage: plic_instance

