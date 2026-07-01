// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Thursday 23 April 2020 05:30:48 PM IST

*/

package qspi_template;
	import qspi::*;


(*descending_urgency="qspi.ifc.rl_data_read_phase,qspi.rl_axi4l_wr_req"*)
(*descending_urgency="qspi.ifc.rl_data_write_phase,qspi.rl_axi4l_rd_req"*)
	(*synthesize*)
  module mkinst_qspi_axi4l(Ifc_qspi_axi4l#(32, 32, 0, 0, 32, 64, 0));      
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkqspi_axi4l#('h0, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_qspi_axi4l
	/*(*synthesize*)
  module mkinst_qspi_apb(Ifc_qspi_apb#(32, 32, 0, 0, 32, 64, 0));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkqspi_apb#('h0, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_qspi_apb*/
endpackage
