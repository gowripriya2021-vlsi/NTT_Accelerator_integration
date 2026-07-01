// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Sunday 19 April 2020 10:45:27 PM IST

*/
package clint_instance ;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;

  import clint        :: * ;

  `include "Logger.bsv"
  `define base 'hc0000000

  (*synthesize*)
  module mkinst_clintaxi4l(Ifc_clint_axi4l#(32, 64, 0, 8, 1));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkclint_axi4l#(0, `base,clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_clintaxi4l
  (*synthesize*)
  module mkinst_clintapb(Ifc_clint_apb#(32, 64, 0, 8, 1));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkclint_apb#(0, `base,clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_clintapb
  (*synthesize*)
  module mkinst_clintaxi4l_32(Ifc_clint_axi4l#(32, 32, 0, 8, 1));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkclint_axi4l#(0, `base,clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_clintaxi4l_32
  (*synthesize*)
  module mkinst_clintapb_32(Ifc_clint_apb#(32, 32, 0, 8, 1));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkclint_apb#(0, `base,clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_clintapb_32
  /*(*synthesize*)
  module mkinst_clintaxi4(Ifc_clint_axi4#(4, 32, 64, 0, 8, 1));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkclint_axi4#(`base,clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_clintaxi4*/
endpackage: clint_instance

