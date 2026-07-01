/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved. See LICENSE.incore for more details.
  Created On:  Thu May 05, 2022 22:40:42 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks
 */
package fbox;
`ifdef EXT_D
  `define dpfpu
`endif
`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import recFN    :: *;
  import fma      :: *;
  import fpu_recfn:: *;
  import Retiming :: *;
  import Vector   :: *;
  import resize   :: *;

  `include "fpu.defines"

  export ModConfig;
  export ModName;
  export Recfmt;
  export IEEE;
  export to_ieee;
  export to_recfn;
  export FBoxIn_recfn;
  export FBoxIn_ieee;
  export FBoxRdy;
  export FBoxOut_recfn;
  export FBoxOut_ieee;
  export Ifc_retimed;
  export Ifc_fbox_recfn;
  export mkfbox_recfn;
  export Ifc_fpu_recfn;
  export fn_fpu_xfrm_inputs;
  export fn_fpu_xfrm_outputs;

  typedef Ifc_fpu_recfn#(expwidth,sigwidth,xlen)
    Ifc_fbox_recfn#(numeric type expwidth,numeric type sigwidth,numeric type xlen);

  typedef Ifc_fpu#(expwidth,sigwidth,xlen)
    Ifc_fbox_ieee#(numeric type expwidth,numeric type sigwidth,numeric type xlen);


  function FBoxIn_recfn#(xlen,expwidth,sigwidth) fn_fpu_xfrm_inputs(
       FBoxIn_ieee#(xlen,expwidth,sigwidth) in) provisos(
      Add#(2, a__, expwidth),
    Add#(23, b__, TAdd#(expwidth, sigwidth)),
    Add#(32, c__, TAdd#(expwidth, sigwidth))
  );
    Recfmt#(expwidth,sigwidth) _1 = to_recfn(resize(in.op1));
    Recfmt#(expwidth,sigwidth) _2 = to_recfn(resize(in.op2));
    Recfmt#(expwidth,sigwidth) _3 = to_recfn(resize(in.op3));
    Bool lv_no_transform = (in.opcode[2] == 1 && in.f7[6:1] == `FCVT_I2F_f7);
    FBoxIn_recfn#(xlen,expwidth,sigwidth) out = FBoxIn_recfn{
      op1: (lv_no_transform) ? resize(in.op1):resize(_1),
      op2: (lv_no_transform) ? resize(in.op2):resize(_2),
      op3: (lv_no_transform) ? resize(in.op3):resize(_3),
      opcode: in.opcode,
      f7:     in.f7,
      f3:     in.f3,
      imm:    in.imm,
      rm:     in.rm,
      issp:   in.issp
    };
      return out;  
  endfunction

  function FBoxOut_ieee#(xlen,expwidth,sigwidth) fn_fpu_xfrm_outputs(
      FBoxOut_recfn#(xlen,expwidth,sigwidth) in,
      Bit#(7) f7, Bit#(4) opcode) provisos(
    Add#(3, a__, TAdd#(expwidth, sigwidth)),
    Add#(b__, c__, TAdd#(1, TAdd#(expwidth, sigwidth))),
    Add#(1, d__, TAdd#(sigwidth, expwidth)),
    Add#(b__, 32, TAdd#(expwidth, sigwidth))
  );
 
    let lv_res = in;
    Recfmt#(expwidth,sigwidth) lv_out_val = resize(lv_res.fbox_result);
    Bit#(TAdd#(expwidth,sigwidth)) _res = to_ieee(lv_out_val);
    Bool lv_no_transform = opcode[2] == 1 && 
        (f7[6:1] == `FCMP_f7 || f7[6:1] == `FCLASS_f7 || 
          f7[6:1] == `FCVT_F2I_f7);
    return FBoxOut_ieee{fbox_result: (lv_no_transform)? resize(lv_res.fbox_result):resize(_res),
      fbox_flags: lv_res.fbox_flags};
  endfunction

  `ifdef fbox_noinline
    (*synthesize*)
  `endif
  module [Module] mkspfma(Ifc_fma#(8,24));
    ModConfig spcfg[4] = {
     ModConfig{name: `SPFMA_STAGE_0, in: `SPFMA_STAGE_0_IN, out: `SPFMA_STAGE_0_OUT},
     ModConfig{name: `SPFMA_STAGE_1, in: `SPFMA_STAGE_1_IN, out: `SPFMA_STAGE_1_OUT},
     ModConfig{name: `SPFMA_STAGE_2, in: `SPFMA_STAGE_2_IN, out: `SPFMA_STAGE_2_OUT},
     ModConfig{name: `SPFMA_STAGE_3, in: `SPFMA_STAGE_3_IN, out: `SPFMA_STAGE_3_OUT}
    }; 
    Ifc_fma#(8,24) temp <- mkfma(arrayToVector(spcfg));
    return temp;
  endmodule

  `ifdef fbox_noinline
    (*synthesize*)
  `endif
  module [Module] mkdpfma(Ifc_fma#(11,53));
    ModConfig dpcfg[4] = {
     ModConfig{name: `DPFMA_STAGE_0, in: `DPFMA_STAGE_0_IN, out: `DPFMA_STAGE_0_OUT},
     ModConfig{name: `DPFMA_STAGE_1, in: `DPFMA_STAGE_1_IN, out: `DPFMA_STAGE_1_OUT},
     ModConfig{name: `DPFMA_STAGE_2, in: `DPFMA_STAGE_2_IN, out: `DPFMA_STAGE_2_OUT},
     ModConfig{name: `DPFMA_STAGE_3, in: `DPFMA_STAGE_3_IN, out: `DPFMA_STAGE_3_OUT}
    };
    Ifc_fma#(11,53) temp <- mkfma(arrayToVector(dpcfg));
    return temp;
  endmodule

  `ifdef fbox_noinline
  (*synthesize*)
  `endif
  (*conflict_free="ma_inputs,rl_sp_divo_rdy"*)
  `ifdef dpfpu
  (*conflict_free="ma_inputs,rl_dp_divo_rdy"*)
  `endif
  (*conflict_free="ma_inputs,rl_capture_output"*)
  (*conflict_free="rl_sp_divo_rdy,rl_capture_output"*)
  `ifdef dpfpu
  (*conflict_free="rl_dp_divo_rdy,rl_capture_output"*)
  `endif
  module mkfbox_recfn#(parameter Bit#(`xlen) hartid, parameter Bool cvt_fmv)
    (Ifc_fbox_recfn#(`expwidth,`sigwidth,`xlen)) provisos(
      );
    let _spfma <- mkspfma();
    Ifc_fma#(`expwidth,`sigwidth) _dpfma;
    `ifdef dpfpu
      _dpfma <- mkdpfma();
    `else
      _dpfma = _spfma;
    `endif
    let _ifc();
    mkfpu_recfn#(hartid,`FORDERING_DEPTH,_spfma,_dpfma,cvt_fmv) _temp(_ifc());
    return _ifc;
  endmodule

endpackage
