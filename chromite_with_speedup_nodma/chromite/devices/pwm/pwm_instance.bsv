// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd.
// see LICENSE.incore for more details on licensing terms

package pwm_instance;

  import pwm   :: *;

  `define PWM_BASE_ADDR 'h30000

  (*synthesize*)
  module mkinst_pwmaxi4l(Ifc_pwm_axi4l#(32, 32, 0, 16, 2, 1));
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    let ifc();
     mkpwm_axi4l#(`PWM_BASE_ADDR, clk, rst, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_pwmaxi4l

  (*synthesize*)
  module mkinst_pwmapb(Ifc_pwm_apb#(32, 32, 0, 16, 2, 0));
    let clk <-exposeCurrentClock;
    let rst <-exposeCurrentReset;
    let ifc();
    mkpwm_apb#(`PWM_BASE_ADDR, clk, rst, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_pwmapb

  (*synthesize*)
  module mkinst_pwmaxi4l_with_ext#(Clock eclk, Reset erst)(Ifc_pwm_axi4l#(32, 32, 0, 16, 2, 0));
    let clk <-exposeCurrentClock;
    let rst <-exposeCurrentReset;
    let ifc();
    mkpwm_axi4l#(`PWM_BASE_ADDR, eclk, erst, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_pwmaxi4l_with_ext

  (*synthesize*)
  module mkinst_pwmapb_with_ext#(Clock eclk, Reset erst)(Ifc_pwm_apb#(32, 32, 0, 16, 2, 0));
    let clk <-exposeCurrentClock;
    let rst <-exposeCurrentReset;
    let ifc();
    mkpwm_apb#(`PWM_BASE_ADDR, eclk, erst, clk, rst) _temp(ifc);
    return ifc;
  endmodule:mkinst_pwmapb_with_ext

endpackage
