// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms

package aclint_instance ;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;

  import aclint        :: * ;

  `include "Logger.bsv"
  `define base 'hc0000000

  (*synthesize*)
  module mkinst_aclintaxi4l(Ifc_aclint_axi4l#(32, 64, 0, 8, 1, 1, 1));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkaclint_axi4l#(`base,32'h00000001,32'h00000001,32'h00000001,32'h00000001,clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_aclintaxi4l
  
  (*synthesize*)
  module mkinst_aclintapb(Ifc_aclint_apb#(32, 64, 0, 8, 1, 6, 8));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkaclint_apb#(`base,32'h00000001,32'h00000001,32'h00000001,32'h00000001,clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_aclintapb
  
  (*synthesize*)
  module mkinst_aclintaxi4l_32(Ifc_aclint_axi4l#(32, 32, 0, 8, 1, 6, 8));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkaclint_axi4l#(`base,32'h00000001,32'h00000001,32'h00000001,32'h00000001,clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_aclintaxi4l_32
  
  (*synthesize*)
  module mkinst_aclintapb_32(Ifc_aclint_apb#(32, 32, 0, 8, 1, 6, 8));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkaclint_apb#(`base,32'h00000001,32'h00000001,32'h00000001,32'h00000001,clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_aclintapb_32
  
  /*(*synthesize*)
  module mkinst_aclintaxi4(Ifc_aclint_axi4#(4, 32, 0, 8, 1,6,8));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkaclint_axi4#(`base,32'h00000001,32'h00000001,32'h00000001,32'h00000001,clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_aclintaxi4*/
endpackage: aclint_instance
