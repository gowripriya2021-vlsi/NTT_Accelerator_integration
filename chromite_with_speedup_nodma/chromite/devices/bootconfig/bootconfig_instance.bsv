// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Friday 26 June 2020 03:43:52 PM

*/
package bootconfig_instance ;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;
	import bootconfig   :: * ;

	(*synthesize*)
  module mkinst_bootconfigaxi4l(Ifc_bootconfig_axi4l#(16, 32, 0, 2));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkbootconfig_axi4l#('h100, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_bootconfigaxi4l
	(*synthesize*)
  module mkinst_bootconfigapb(Ifc_bootconfig_apb#(16, 32, 0, 4));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkbootconfig_apb#('h100, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_bootconfigapb

  `include "Logger.bsv"
endpackage: bootconfig_instance

