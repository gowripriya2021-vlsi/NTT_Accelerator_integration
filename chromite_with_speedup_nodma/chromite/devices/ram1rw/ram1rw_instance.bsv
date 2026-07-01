// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details 
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Sunday 19 April 2020 05:16:02 PM IST

*/
package ram1rw_instance ;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;

  import ram1rw       :: * ;
  import ram1rw_user  :: * ;
  import mem_config   :: * ;

  `include "Logger.bsv"
  (*synthesize*)
  module mkinst_ram1rwuser(Ifc_ram1rw_user#(1024, 32, 1));
    let ifc();
    mk_ram1rw_user#(replicate(tagged File "boot"), "nc") _temp(ifc);
    return ifc;
  endmodule:mkinst_ram1rwuser
  (*synthesize*)
  module mkinst_ram1rwapb(Ifc_ram1rw_apb#(32, 32, 0, 1024, 32, 1));
    let ifc();
    mk_ram1rw_apb#('h100, replicate(tagged File "boot"), "nc") _temp(ifc);
    return ifc;
  endmodule:mkinst_ram1rwapb
  (*synthesize*)
  module mkinst_ram1rwaxi4l(Ifc_ram1rw_axi4l#(32, 32, 0, 1024, 32, 1));
    let ifc();
    mk_ram1rw_axi4l#('h100, replicate(tagged File "boot"), "nc") _temp(ifc);
    return ifc;
  endmodule:mkinst_ram1rwaxi4l
  (*synthesize*)
  module mkinst_ram1rwaxi4(Ifc_ram1rw_axi4#(4, 32, 32, 0, 1024, 32, 1));
    let ifc();
    mk_ram1rw_axi4#('h100, replicate(tagged File "boot"), "nc") _temp(ifc);
    return ifc;
  endmodule:mkinst_ram1rwaxi4
endpackage: ram1rw_instance

