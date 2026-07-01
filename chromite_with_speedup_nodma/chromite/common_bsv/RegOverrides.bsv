/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved. See LICENSE.incore for more details.
  Created On:  Wed Jun 15, 2022 10:30:26 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks

  On importing this package, all mkReg*,mkCReg* and mkConfigReg* modules are replaced with their
  asynchronous versions by default. To use the original modules with synchronous resets the
  `Prelude::` prefix should be used. For example to use the original mkReg module use
  `Prelude::mkReg`. For scheduling attributes, refer to the scheduling of mkRegA, mkCRegA and 
  mkConfigRegA modules in the reference manual.
 */
package RegOverrides;

  import ConfigReg  :: *;
  import DReg       :: *;

  export mkReg;
  export mkRegU;
  export mkCReg;
  export mkCRegU;
  export mkConfigReg;
  export mkConfigRegU;
  export mkDReg;
  export mkDRegU;

 

  module mkReg#(parameter a_type resetval)(Reg#(a_type))
    provisos (Bits#(a_type, sizea));
    let _ifc();
    mkRegA#(resetval) _temp(_ifc());
    return _ifc;
  endmodule

  module mkRegU(Reg#(a_type))
    provisos (Bits#(a_type, sizea));
    let _ifc();
    mkRegA#(?) _temp(_ifc());
    return _ifc;
  endmodule

  module mkCReg#(parameter Integer n, parameter a_type resetval)  (Reg#(a_type) ifc[])
    provisos (Bits#(a_type, sizea));
    let _ifc();
    mkCRegA#(n,resetval) _temp(_ifc());
    return _ifc;
  endmodule

  module mkCRegU#(parameter Integer n)(Reg#(a_type) ifc[])
    provisos (Bits#(a_type, sizea));
    let _ifc();
    mkCRegA#(n,?) _temp(_ifc());
    return _ifc;
  endmodule

  module mkConfigReg#(parameter a_type resetval)(Reg#(a_type))
    provisos (Bits#(a_type, sizea));
    let _ifc();
    mkConfigRegA#(resetval) _temp(_ifc());
    return _ifc;
  endmodule

  module mkConfigRegU(Reg#(a_type))
    provisos (Bits#(a_type, sizea));
    let _ifc();
    mkConfigRegA#(?) _temp(_ifc());
    return _ifc;
  endmodule

  module mkDReg#(a_type dflt_rst_val)(Reg#(a_type))
    provisos (Bits#(a_type, sizea));
    let _ifc();
    mkDRegA#(dflt_rst_val) _temp(_ifc());
    return _ifc;
  endmodule

  module mkDRegU#(a_type dflt_rst_val)(Reg#(a_type))
    provisos (Bits#(a_type, sizea));
    let _ifc();
    mkDRegA#(dflt_rst_val) _temp(_ifc());
    return _ifc;
  endmodule

endpackage
