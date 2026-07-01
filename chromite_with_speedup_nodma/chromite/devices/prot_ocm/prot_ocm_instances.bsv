// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd.
// see LICENSE.incore for more details on licensing terms
/*
Author: Babu P S, babu.ps@incoresemi.com @eflaner
Created on: Thursday 30 September 2021
*/
package prot_ocm_instances ;
  import prot_ocm       :: * ;
  import Vector       :: * ;
  import mem_config   :: * ;

  (*synthesize*)
  module mkinst_prot_ocm_axi4l(Ifc_ocmconfig_axi4l#(64, 32, 0, 4, 32, 32, 0, 1024, 32, 1));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mk_prot_ocm_axi4l#('h1000, 'h100, replicate(tagged File "boot"), "nc", clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_prot_ocm_axi4l

  (*synthesize*)
  module mkinst_prot_ocm_apb(Ifc_ocmconfig_apb#(64, 32, 0, 4, 32, 32, 0, 1024, 32, 1));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mk_prot_ocm_apb#('h1000, 'h100, replicate(tagged File "boot"), "nc", clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_prot_ocm_apb

endpackage: prot_ocm_instances


