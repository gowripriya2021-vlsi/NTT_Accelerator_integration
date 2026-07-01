// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Thursday 23 April 2020 05:30:48 PM IST

*/

package gpio_instance;
	import gpio::*;
	(*synthesize*)
  module mkinst_gpioaxi4l(Ifc_gpio_axi4l#(16, 32, 0, 16, 16));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkgpio_axi4l#('h100, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_gpioaxi4l
	(*synthesize*)
  module mkinst_gpioapb(Ifc_gpio_apb#(16, 32, 0, 16,16));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
    mkgpio_apb#('h100, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_gpioapb
endpackage
