// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 05 January 2022 08:15:03 PM

*/
package debug_instance;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;
  import debug        :: * ;
  import debug_types  :: * ;
  import DefaultValue :: * ;

  `define base 0

  `include "Logger.bsv"
  (*synthesize*)
  // the following is required because control is updated by both.
  module [Module] mkinst_debugapb(Ifc_debug_apb#(32, 64, 0, 16, 12, 1, 1));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkdebug_apb#(defaultValue, `base, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_debugapb
  (*synthesize*)
  // the following is required because control is updated by both.
  module [Module] mkinst_debugaxi4l(Ifc_debug_axi4l#(32, 64, 0, 16, 12, 1, 1));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkdebug_axi4l#(defaultValue, `base, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_debugaxi4l

endpackage:debug_instance

