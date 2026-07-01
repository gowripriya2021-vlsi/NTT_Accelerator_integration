/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved. See LICENSE.incore for more details.
  Created On:  Wed Apr 06, 2022 09:22:17 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks
*/
package testbench;
`ifdef EXT_D
  `define dpfpu
`endif
`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import fpu_recfn    :: *;
  import recFN        :: *;
  import FIFOF        :: *;
  import Vector       :: *;
  import fma          :: *;
  import GetPut       :: *;
  import Connectable  :: *;
  import SpecialFIFOs :: *;
  import resize       :: *;

  `include "Logger.bsv"

  `define elemwidth TMax#(`xlen,TAdd#(`expwidth,`sigwidth))

  typedef struct{
    Bool incvt;
    Bool outcvt;
    Bool outsp;
    Bit#(`elemwidth) op1;
    Bit#(`elemwidth) op2;
    Bit#(`elemwidth) op3;
    Bit#(4) opcode;
    Bit#(7) f7;
    Bit#(3) f3;
    Bit#(2) imm;
    Bit#(3) rm;
    Bool    issp;
  } Test_in deriving(Bits,Eq,FShow);

  typedef FBoxOut_ieee#(`xlen, `expwidth,`sigwidth) Test_out;
  typedef FBoxRdy Test_rdy;
  typedef Bit#(`xlen) XLEN;
  typedef Bit#(TAdd#(`expwidth,`sigwidth)) FLEN;

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

  (*synthesize*)
  (*conflict_free="ma_inputs,rl_sp_divo_rdy"*)
  `ifdef dpfpu
  (*conflict_free="ma_inputs,rl_dp_divo_rdy"*)
  `endif
  (*conflict_free="ma_inputs,rl_capture_output"*)
  (*conflict_free="rl_sp_divo_rdy,rl_capture_output"*)
  `ifdef dpfpu
  (*conflict_free="rl_dp_divo_rdy,rl_capture_output"*)
  `endif
  module mkfpu_inst(Ifc_fpu_recfn#(`expwidth,`sigwidth,`xlen));
    /* ModConfig dpcfg[4] = { */
    /*  ModConfig{name: Pre,in: 2, out: 2}, */
    /*  ModConfig{name: Mac, in: 0, out: 2}, */
    /*  ModConfig{name: Post, in: 0, out: 2}, */
    /*  ModConfig{name: Round, in: 0, out: 2} */
    /* }; */ 
    /* ModConfig spcfg[4] = { */
    /*  ModConfig{name: Pre,in: 1, out: 1}, */
    /*  ModConfig{name: Mac, in: 0, out: 1}, */
    /*  ModConfig{name: Post, in: 0, out: 1}, */
    /*  ModConfig{name: Round, in: 0, out: 1} */
    /* }; */
    let _spfma <- mkspfma();
    Ifc_fma#(`expwidth,`sigwidth) _dpfma;
    `ifdef dpfpu
      _dpfma <- mkdpfma();
    `else
      _dpfma = _spfma;
    `endif
    /* else */
      /* _dpfma = _spfma; */
    let _ifc();
    mkfpu_recfn#(0,`FORDERING_DEPTH,_spfma,_dpfma,False) _temp(_ifc());
    return _ifc;
  endmodule

  interface Ifc_test;
    interface Put#(Test_in) in;
    interface Get#(Test_out) out;
    method FBoxRdy rdy;
  endinterface
  module mktest(Ifc_test);

    Bool dpfpu = ((`expwidth+`sigwidth) == 64);
    let fpu <- mkfpu_inst();
    FIFOF#(Test_in) ff_in <- mkBypassFIFOF();
    FIFOF#(Test_in) ff_req_queue <- mkSizedFIFOF(15);
    FIFOF#(FBoxOut_ieee#(`xlen,`expwidth,`sigwidth)) ff_out <- mkBypassFIFOF();
    FIFOF#(FBoxOut_recfn#(`xlen,`expwidth,`sigwidth)) ff_fbox_out <-
    mkSizedFIFOF(2);
    Vector#(3,Ifc_fNToRecFN#(`expwidth,`sigwidth))  in_cvt  <- replicateM(mk_fNToRecFN());
    Vector#(3,Ifc_fNToRecFN#(8,24))  in_cvt_sp;

    Ifc_recFNToFN#(`expwidth,`sigwidth)             out_cvt <- mk_recFNToFN(); 
    Ifc_recFNToFN#(8,24)             out_cvt_sp ; 
    if (dpfpu) begin
      in_cvt_sp <- replicateM(mk_fNToRecFN());
      out_cvt_sp <- mk_recFNToFN();
    end
    mkConnection(ff_fbox_out,fpu.tx_output);
    rule rl_drive_input;
      let lv_input = ff_in.first;
      Bit#(TMax#(`xlen,TAdd#(TAdd#(`expwidth,`sigwidth),1))) ops[3];
      `logLevel(testbench,1,$format("TB: Ready:",fshow(fpu.mv_ready())))
      `logLevel(testbench,1,$format("TB: Got Inputs:",fshow(ff_in.first)))
      if(lv_input.incvt) begin
        Vector#(3,Recfmt#(`expwidth,`sigwidth)) cvt_ops;
        if(dpfpu && lv_input.issp) begin
          in_cvt_sp[0].request(truncate(lv_input.op1));
          in_cvt_sp[1].request(truncate(lv_input.op2));
          in_cvt_sp[2].request(truncate(lv_input.op3));
          cvt_ops[0] = {maxBound,in_cvt_sp[0].out()};
          cvt_ops[1] = {maxBound,in_cvt_sp[1].out()};
          cvt_ops[2] = {maxBound,in_cvt_sp[2].out()};
        end
        else begin
          in_cvt[0].request(truncate(lv_input.op1));
          in_cvt[1].request(truncate(lv_input.op2));
          in_cvt[2].request(truncate(lv_input.op3));
          cvt_ops[0] = in_cvt[0].out();
          cvt_ops[1] = in_cvt[1].out();
          cvt_ops[2] = in_cvt[2].out();
        end
        ops[0] = signExtend(cvt_ops[0]);        
        ops[1] = signExtend(cvt_ops[1]); 
        ops[2] = signExtend(cvt_ops[2]); 
      end
      else begin
        ops[0] = signExtend(lv_input.op1);
        ops[1] = signExtend(lv_input.op2);
        ops[2] = signExtend(lv_input.op3);
      end
      FBoxIn_recfn#(`xlen,`expwidth,`sigwidth) lv_in = FBoxIn_recfn{
          op1: ops[0],
          op2: ops[1],
          op3: ops[2],
          rm: lv_input.rm,
          f7: lv_input.f7,
          opcode: lv_input.opcode,
          issp: lv_input.issp,
          f3: lv_input.f3,
          imm: lv_input.imm
      };
      `logLevel(testbench,1,$format("TB: Sending Inputs:",fshow(lv_in)))
      fpu.ma_inputs(lv_in);
      ff_req_queue.enq(lv_input);
      ff_in.deq;
    endrule
    
    rule rl_process_output;
      let lv_input = ff_req_queue.first;
      let lv_output = ff_fbox_out.first;
      `logLevel(testbench,1,$format("TB: For Input:",fshow(lv_input)))
      `logLevel(testbench,1,$format("TB: FBox Output:",fshow(lv_output)))
      FBoxOut_ieee#(`xlen,`expwidth,`sigwidth) lv_out;
      if(lv_input.outcvt) begin
        Bit#(TAdd#(`expwidth,`sigwidth)) cvt_op;
        if(dpfpu && lv_input.outsp) begin
          out_cvt_sp.request(truncate(lv_output.fbox_result));
          cvt_op = {maxBound, out_cvt_sp.out};
        end
        else begin
          out_cvt.request(truncate(lv_output.fbox_result));
          cvt_op = out_cvt.out;
        end
        lv_out.fbox_flags = lv_output.fbox_flags;
        lv_out.fbox_result = resize(cvt_op);
      end
      else begin
        lv_out.fbox_flags = lv_output.fbox_flags;
        lv_out.fbox_result = truncate(lv_output.fbox_result);
      end
      ff_out.enq(lv_out);
      ff_fbox_out.deq;
      ff_req_queue.deq;
    endrule
    interface in = toPut(ff_in);
    interface out = toGet(ff_out);
    method rdy = fpu.mv_ready;
  endmodule
endpackage
