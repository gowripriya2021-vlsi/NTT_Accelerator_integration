// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details 
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Sunday 19 April 2020 05:16:02 PM IST

*/
package ram2rw_instance ;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;

  import ram2rw       :: * ;
  import ram2rw_user  :: * ;
  import mem_config   :: * ;

  `include "Logger.bsv"
  (*synthesize*)
  module mkinst_ram2rwuser(Ifc_ram2rw_user#(1024, 32, 1));
    let ifc();
    mk_ram2rw_user#(replicate(tagged File "boot"), "nc") _temp(ifc);
    return ifc;
  endmodule:mkinst_ram2rwuser
  (*synthesize*)
  module mkinst_ram2rwapb(Ifc_ram2rw_apb#(32, 32, 0, 1024, 32, 1));
    let ifc();
    mk_ram2rw_apb#('h100, replicate(tagged File "boot"), "nc") _temp(ifc);
    return ifc;
  endmodule:mkinst_ram2rwapb
  (*synthesize*)
  module mkinst_ram2rwaxi4l(Ifc_ram2rw_axi4l#(32, 32, 0, 1024, 32, 1));
    let ifc();
    mk_ram2rw_axi4l#('h100, replicate(tagged File "boot"), "nc") _temp(ifc);
    return ifc;
  endmodule:mkinst_ram2rwaxi4l
  (*synthesize*)
  module mkinst_ram2rwaxi4(Ifc_ram2rw_axi4#(4, 32, 32, 0, 1024, 32, 1));
    let ifc();
    mk_ram2rw_axi4#('h100, replicate(tagged File "boot"), "nc") _temp(ifc);
    return ifc;
  endmodule:mkinst_ram2rwaxi4
endpackage: ram2rw_instance

