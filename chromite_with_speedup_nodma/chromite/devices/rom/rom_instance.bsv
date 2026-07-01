// Copyright (c) InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Sunday 19 April 2020 01:00:35 PM IST

*/
package rom_instance ;

import rom      :: * ;
import rom_user :: * ;
import Vector   :: * ;

(*synthesize*)
module mkinst_romuser(Ifc_rom_user#(1024, 64, 1));
  let ifc();
  mk_rom_user#(replicate("boot")) _temp(ifc);
  return ifc;
endmodule:mkinst_romuser
(*synthesize*)
module mkinst_romapb(Ifc_rom_apb#(32, 64, 0, 1024, 64, 1));
  let ifc();
  mk_rom_apb#('h1000, replicate("boot")) _temp(ifc);
  return ifc;
endmodule:mkinst_romapb
(*synthesize*)
module mkinst_romaxi4l(Ifc_rom_axi4l#(32, 64, 0, 1024, 64, 1));
  let ifc();
  mk_rom_axi4l#('h1000, replicate("boot")) _temp(ifc);
  return ifc;
endmodule:mkinst_romaxi4l
(*synthesize*)
module mkinst_romaxi4(Ifc_rom_axi4#(4, 32, 64, 0, 1024, 64, 1));
  let ifc();
  mk_rom_axi4#('h1000, replicate("boot")) _temp(ifc);
  return ifc;
endmodule:mkinst_romaxi4

endpackage: rom_instance

