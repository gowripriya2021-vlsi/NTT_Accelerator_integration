/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved. See LICENSE.incore for more details.
  Created On:  Thu Mar 31, 2022 10:58:57 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks
*/
package fpu_recfn;

`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import recFN    :: *;
  import ConfigReg :: *;
  import fma      :: *;
  import TxRx     :: *;
  import FIFOF    :: *;
  import Vector   :: *;
  import Retiming :: *;
  import resize   :: *;

  `include "fpu.defines"
  `include "Logger.bsv"

  /*doc:func: This function checks whether the given value in recoded format is a valid nan boxed value or
   * not. The check is performed by testing the special flag in the dont care bits of the exponent
   * when the value is a NaN.*/
  function Bool isNanBox(Recfmt#(expwidth,sigwidth) a) provisos(
    Add#(3, a__, TAdd#(expwidth, sigwidth))
      );
    Bit#(4) x = truncateLSB(a);
    Bit#(1) y = truncateLSB(a<<6);
    return unpack((&x) & (y));
  endfunction

  /*doc:func: This function checks whether the given value is a QNaN or not. The check is performed
   * by using the upper 4 bits of the exponent.*/
  function Bool fn_recfn_mem_nan(Recfmt#(expwidth,sigwidth) a) provisos(
    Add#(3, a__, TAdd#(expwidth, sigwidth))
      );
    Bit#(4) x = truncateLSB(a<<1);
    return unpack(&x);
  endfunction

  /*doc:func: Helper function to perform a bit replacement in a bit vector using a mask.*/
  function Bit#(a) masked_replace(Bit#(a) val, Bit#(a) mask, Bit#(a) replace);
    Bit#(a) ret_val = val;
    for(Integer i=0;i<valueof(a);i=i+1) begin
      if(mask[i] == 1)
        ret_val[i] = replace[i];
      else 
        ret_val[i] = val[i];
    end
    return ret_val;
  endfunction

  /*doc:func: This function sets the special flags in the dont care bits of the exponent when the
   * output of an operation is a NaN. This ensures that the flags are set properly always and
   * doesn't cause any errors when the outputs are used as inputs for subsequent operations.*/
  function Recfmt#(expwidth,sigwidth) fn_sanitise_nan(Recfmt#(expwidth,sigwidth) a);
    let lv_flen = valueof(TAdd#(expwidth,sigwidth));
    let lv_sigwidth = valueof(sigwidth);
    let lv_expwidth = valueof(expwidth);
    Bit#(TSub#(sigwidth,1)) sig = resize(a);
    Bit#(1) is_nan = resizeLSB(sig);
    Bit#(20) msb = resizeLSB(sig);
    Bit#(3) flags = resizeLSB(a<<1);
    Bit#(1) sign = resize(a);
    Bit#(1) hidden = resize(msb);
    Recfmt#(expwidth,sigwidth) b = a;
    Bit#(3) _temp = (flags==7)?3'b111:3'b000;
    Recfmt#(expwidth,sigwidth) mask = resize(_temp) << (lv_flen-6);
    Recfmt#(expwidth,sigwidth) replace = (resize({is_nan,hidden,&msb})<<(lv_flen-6));
    b = masked_replace(a,mask,replace);
    return b;
  endfunction
  
  // Datatype to specify the IEEE number. Its a simple addition of bitwidths but helps keep the same
  // syntax as the recoded format and helps in parameterising functions. 
  typedef Bit#(TAdd#(expwidth,sigwidth)) IEEE#(numeric type expwidth,numeric type sigwidth);

  /*doc:func: Tests whether a given FP value in IEEE format is a QNaN.*/
  function Bool fn_ieee_mem_nan(IEEE#(expwidth,sigwidth) a);
    let lv_sigwidth = valueof(sigwidth);
    Bit#(expwidth) exp = truncateLSB(a<<1);
    Bit#(sigwidth) sig = truncate(a);
    return exp==maxBound && (|sig == 1) && a[lv_sigwidth-2] == 1;
  endfunction

  /*doc:func: Converts from the custom recoded format in the register to the ieee754 format to
   * expose to the outside world. This function sets the bits according to the special flags and
   * ensures that the bit at index 32 is correctly expressed.*/
  function Bit#(flen) to_ieee(Recfmt#(expwidth,sigwidth) in) provisos(
    Add#(a__, 32, flen),
    Add#(1, b__, TAdd#(expwidth, sigwidth)),
    Add#(1, b__, TAdd#(sigwidth, expwidth)),
    Add#(a__, c__, TAdd#(1, TAdd#(expwidth, sigwidth))),
    Add#(3, d__, TAdd#(expwidth, sigwidth)),
    Add#(sigwidth, expwidth, flen)
  );
    Bool isnan = fn_recfn_mem_nan(in);
    Bit#(flen) out;
    Bit#(flen) dp_out = recfn_to_fn(in);
    Recfmt#(8,24) sp = resize(in);
    Bit#(32) sp_out = recfn_to_fn(sp);
    Bool dpfpu = valueof(TAdd#(expwidth,sigwidth)) == 64;
    if(dpfpu) begin
      if(isnan) begin
        out =  masked_replace({truncateLSB(dp_out),sp_out},1<<32,(resize(in[valueof(flen)-5])<<32));
      end
      else begin
        out = dp_out;
      end
    end
    else
      out = dp_out;
    return out;
  endfunction

  /*doc:func: This function converts from a ieee754 value to the custom recoded format to store in
   * the registers. It sets the special flags and places the bit at index 32 into the dont care bits
   * so that the value is preserved.*/
  function Recfmt#(expwidth,sigwidth) to_recfn(IEEE#(expwidth,sigwidth) in) provisos(
    Add#(32, a__, TAdd#(expwidth, sigwidth)),
    Add#(2, c__, expwidth),
    Add#(23, b__, TAdd#(expwidth, sigwidth))
  );
    Bool isnan = fn_ieee_mem_nan(in);
    Recfmt#(expwidth,sigwidth) out;
    Recfmt#(expwidth,sigwidth) dp_out = fn_to_recfn(in);
    Bit#(32) sp_in = resize(in);
    Recfmt#(8,24) sp_out = fn_to_recfn(sp_in);
    Bool dpfpu = valueof(TAdd#(expwidth,sigwidth)) == 64;

    if(dpfpu) begin
      if(isnan) begin
        Bit#(52) lsb = resize(in);
        Bit#(20) msb = resizeLSB(lsb);
        Recfmt#(expwidth,sigwidth) special_flags =
                                        resize({pack(isnan),in[valueof(TSub#(sigwidth,21))],&msb});
        out = masked_replace({truncateLSB(dp_out),sp_out},7<<58,(special_flags << 58));
      end
      else
        out = dp_out;
    end
    else
      out = dp_out;
    return out;
  endfunction

  typedef struct{
    Bool dfma;
    Bool ddivsqrt;
    Bool dcvt;
    Bool sfma;
    Bool sdivsqrt;
    Bool singlecycle;
    Bool scvt;
  } FBoxRdy deriving(Bits,FShow,Eq);

  typedef struct{
    Bit#(TMax#(xlen, TAdd#(TAdd#(expwidth,sigwidth),1))) op1;
    Bit#(TMax#(xlen, TAdd#(TAdd#(expwidth,sigwidth),1))) op2;
    Bit#(TMax#(xlen, TAdd#(TAdd#(expwidth,sigwidth),1))) op3;
    Bit#(4) opcode;
    Bit#(7) f7;
    Bit#(3) f3;
    Bit#(2) imm;
    Bit#(3) rm;
    Bool    issp;
  } FBoxIn_recfn#(numeric type xlen, numeric type expwidth, numeric type sigwidth) deriving (Bits,Eq, FShow);

  typedef enum{SPFMA,SPDIVSQRT,SPCVT,SINGLECYCLE,DPFMA,DPDIVSQRT,DPCVT} FBoxOpType deriving
  (Bits,Eq,FShow);

  typedef struct{
    Bit#(TMax#(xlen, TAdd#(TAdd#(expwidth,sigwidth),1))) fbox_result;
    Bit#(5) fbox_flags;
  } FBoxOut_recfn#(numeric type xlen, numeric type expwidth, numeric type sigwidth) deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(TMax#(xlen, TAdd#(expwidth,sigwidth))) op1;
    Bit#(TMax#(xlen, TAdd#(expwidth,sigwidth))) op2;
    Bit#(TMax#(xlen, TAdd#(expwidth,sigwidth))) op3;
    Bit#(4) opcode;
    Bit#(7) f7;
    Bit#(3) f3;
    Bit#(2) imm;
    Bit#(3) rm;
    Bool    issp;
  } FBoxIn_ieee#(numeric type xlen, numeric type expwidth, numeric type sigwidth) deriving (Bits,Eq, FShow);

  typedef struct{
    Bit#(TMax#(xlen, TAdd#(expwidth,sigwidth))) fbox_result;
    Bit#(5) fbox_flags;
  } FBoxOut_ieee#(numeric type xlen, numeric type expwidth, numeric type sigwidth) deriving(Bits, Eq, FShow);

  function Config gen_cfg(Integer flen,Integer xlen);
    if(flen == 64)
      if(xlen == 32)
        return RV32D;
      else
        return RV64D;
    else
      if(xlen == 32)
        return RV32F;
      else
        return RV64F;
  endfunction

  interface Ifc_fpu_recfn#(numeric type expwidth,numeric type sigwidth, numeric type xlen);
    method Action ma_inputs(FBoxIn_recfn#(xlen,expwidth,sigwidth) in);
    method FBoxRdy mv_ready;
    method TXe#(FBoxOut_recfn#(xlen,expwidth,sigwidth)) tx_output;
  endinterface

  interface Ifc_fpu#(numeric type expwidth,numeric type sigwidth, numeric type xlen);
    method Action ma_inputs(FBoxIn_recfn#(xlen,expwidth,sigwidth) in);
    method FBoxRdy mv_ready;
    method TXe#(FBoxOut_recfn#(xlen,expwidth,sigwidth)) tx_output;
  endinterface

  /*doc:mod: This module implements the floating point unit in recoded format. The configuration for
   * fma can be given by using the ModConfig datastructure. The config should be given for both sp
   * and dp modules, but incase the fpu is instantiated only for sp, the config can be a default of
   * None and 0's for stages. */
  module [Module] mkfpu_recfn#(parameter Bit#(xlen) hartid,parameter Integer depth, Ifc_fma#(8,24) spfma, 
      Ifc_fma#(expwidth,sigwidth) dpfma, Bool cvt_fmv)
    (Ifc_fpu_recfn#(expwidth,sigwidth,xlen))
    provisos(
      Add#(expwidth,sigwidth,flen),
      Add#(flen,1,recflen),
      Max#(recflen,xlen,elemwidth),
      Add#(a__, 32, xlen),
      /* Add#(b__, 10, elemwidth), */
      Add#(b__, 10, TMax#(xlen, TAdd#(TAdd#(expwidth, sigwidth), 1))),
      Add#(2, c__, expwidth),
      Add#(sigwidth, d__, recflen),
      Add#(1, e__, TAdd#(sigwidth, expwidth)),
      Add#(1, e__, TAdd#(expwidth, sigwidth)),
      Add#(g__, 33, elemwidth),
      Add#(h__, 1, elemwidth),
      Add#(32, i__, TAdd#(sigwidth, expwidth)),
      Add#(32, i__, TAdd#(expwidth, sigwidth)),
      Add#(j__, TAdd#(sigwidth, sigwidth), TAdd#(1, TMul#(sigwidth, 2))),
      Add#(k__, sigwidth, TAdd#(1, TMul#(sigwidth, 2))),
      Add#(l__, TAdd#(1, TAdd#(expwidth, sigwidth)), elemwidth),
      Add#(m__, 32, elemwidth),
      Add#(n__, flen, elemwidth),
      Add#(p__, TAdd#(1, TAdd#(sigwidth, expwidth)), elemwidth),
      Add#(o__, xlen, elemwidth),
      Add#(23, q__, TAdd#(expwidth, sigwidth)),
      Add#(r__, 32, flen),
      Add#(r__, s__, TAdd#(1, TAdd#(expwidth, sigwidth))),
      Add#(4, u__, TAdd#(expwidth, sigwidth)),
      Add#(3, t__, TAdd#(expwidth, sigwidth)),
      Add#(v__, 32, TMax#(xlen, TAdd#(TAdd#(expwidth, sigwidth), 1))),
      Add#(2, f__, xlen)
      );
    let lv_flen = valueof(flen);
    let lv_xlen = valueof(xlen);
    let dpfpu = (lv_flen == 64);

//    Ifc_fma#(8,24) spfma <- mkfma(spconfig);
    /* let spfma <- mkspfma(); */
    Ifc_divSqrtRecFN_small#(8,24) spdivsqrt <- mk_divSqrtRecFN_small;
    Ifc_compareRecFN#(8,24) spcmp <- mk_compareRecFN;
    /* Ifc_fma#(expwidth,sigwidth) dpfma; */
    Ifc_divSqrtRecFN_small#(expwidth,sigwidth) dpdivsqrt;
    Ifc_compareRecFN#(expwidth,sigwidth) dpcmp;
    Ifc_recFNToRecFN#(expwidth,sigwidth,8,24) dptosp;
    Ifc_recFNToRecFN#(8,24,expwidth,sigwidth) sptodp;    
    Reg#(Bool) spdivo_rdy[2] <- mkCReg(2,False); 
    Reg#(Bool) dpdivo_rdy[2]; 
    Reg#(Bool) spdiv_rdy <- mkConfigReg(True); 
    Reg#(Bool) dpdiv_rdy;
    if(dpfpu) begin
      /* dpfma <- mkfma(dpconfig); */
      dpdivsqrt <- mk_divSqrtRecFN_small;
      dpcmp <- mk_compareRecFN;
      dptosp <- mk_recFNToRecFN;
      sptodp <- mk_recFNToRecFN;
      dpdiv_rdy <- mkConfigReg(True);
      dpdivo_rdy <- mkCReg(2,False);
    end

    FIFOF#(FBoxOpType) ff_ordering <- mkUGSizedFIFOF(depth);
    FIFOF#(FBoxOut_recfn#(xlen,expwidth,sigwidth)) ff_result <- mkUGSizedFIFOF(depth);
    TX#(FBoxOut_recfn#(xlen,expwidth,sigwidth)) tx_fbox_out <- mkTX;

    rule rl_sp_divo_rdy(!spdivo_rdy[0] && !spdiv_rdy);
      if(spdivsqrt.outValid == 1)
        spdivo_rdy[0] <= True;
    endrule

    if(dpfpu) begin
    rule rl_dp_divo_rdy(dpfpu && !dpdivo_rdy[0] && !dpdiv_rdy);
      if(dpdivsqrt.outValid == 1)
        dpdivo_rdy[0] <= True;
    endrule
    end

    rule rl_capture_output(ff_ordering.notEmpty && tx_fbox_out.u.notFull);
      `logLevel(fbox,1,$format("[%2d]FBOX: Waiting for result from ",hartid,fshow(ff_ordering.first)))
      if(dpfpu) begin
        if(ff_ordering.first == DPFMA) begin
          if(dpfma.mv_output_valid) begin
            let {_o, _f} <- dpfma.mav_output();
            Recfmt#(expwidth,sigwidth) _temp = fn_sanitise_nan(_o); 
            tx_fbox_out.u.enq(FBoxOut_recfn{fbox_result: resize(_temp), fbox_flags: _f});
            ff_ordering.deq();
            `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result from DPFMA.",hartid))
          end
        end
        if(ff_ordering.first == DPDIVSQRT) begin
          if(dpdivo_rdy[1])  begin
            Recfmt#(expwidth,sigwidth) _temp = fn_sanitise_nan(dpdivsqrt.out);
            tx_fbox_out.u.enq(FBoxOut_recfn{fbox_result: resize(_temp), 
                                      fbox_flags: dpdivsqrt.exceptionFlags});
            ff_ordering.deq();
            dpdiv_rdy <= True;
            `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result from DPDIVSQRT.",hartid))
          end
        end
        if(ff_ordering.first == DPCVT) begin
          tx_fbox_out.u.enq(ff_result.first);
          ff_result.deq;
          ff_ordering.deq;
          `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result from DPCVT.",hartid))
        end
      end
      if(ff_ordering.first == SPFMA) begin
        if(spfma.mv_output_valid) begin
          let {_o, _f} <- spfma.mav_output();
          tx_fbox_out.u.enq(FBoxOut_recfn{fbox_result: resize_max(_o), fbox_flags: _f});
          ff_ordering.deq();
          `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result from SPFMA.",hartid))
        end
      end
      if(ff_ordering.first == SPDIVSQRT) begin
        if(spdivo_rdy[1])  begin
          tx_fbox_out.u.enq(FBoxOut_recfn{fbox_result: resize_max(spdivsqrt.out), 
                                    fbox_flags: spdivsqrt.exceptionFlags});
          ff_ordering.deq();
          spdiv_rdy<=True;
          `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result from SPDIVSQRT.",hartid))
        end
      end
      if(ff_ordering.first == SPCVT) begin
        tx_fbox_out.u.enq(ff_result.first);
        ff_result.deq;
        ff_ordering.deq;
        `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result from SPCVT.",hartid))
      end
      if(ff_ordering.first == SINGLECYCLE) begin
        tx_fbox_out.u.enq(ff_result.first);
        ff_result.deq;
        ff_ordering.deq;
        `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result from SINGLECYCLE OP.",hartid))
      end
    endrule

    FBoxRdy lv_ready;

    if(dpfpu) begin
      lv_ready = FBoxRdy{
        sfma: spfma.mv_ready && ff_ordering.notFull,
        dfma: dpfma.mv_ready && ff_ordering.notFull,
        ddivsqrt: unpack(dpdivsqrt.inReady) && ff_ordering.notFull && dpdiv_rdy,
        dcvt: True && ff_ordering.notFull,
        sdivsqrt: unpack(spdivsqrt.inReady) && ff_ordering.notFull && spdiv_rdy,
        singlecycle: True && ff_ordering.notFull,
        scvt: True && ff_ordering.notFull
      };
    end
    else begin
      lv_ready = FBoxRdy{
        sfma: spfma.mv_ready && ff_ordering.notFull,
        dfma: False,
        ddivsqrt: False,
        dcvt: False,
        sdivsqrt: unpack(spdivsqrt.inReady) && ff_ordering.notFull && spdiv_rdy,
        singlecycle: True && ff_ordering.notFull,
        scvt: True && ff_ordering.notFull
      };
    end

    method Action ma_inputs(FBoxIn_recfn#(xlen,expwidth,sigwidth) inputs);
      `logLevel(fbox,1,$format("[%2d]FBOX: Inputs: ",hartid,fshow(inputs)))
      Recfmt#(expwidth,sigwidth) op1 = resize(inputs.op1);
      Recfmt#(expwidth,sigwidth) op2 = resize(inputs.op2);
      Recfmt#(expwidth,sigwidth) op3 = resize(inputs.op3);
      Recfmt#(expwidth,sigwidth) can1;
      Recfmt#(expwidth,sigwidth) can2;
      Recfmt#(expwidth,sigwidth) can3;
      // Sign bit to set in c input(0) for FMUL operations to ensure that output sign is correct.
      Bit#(1) fp_sign;
      if(dpfpu) begin
        Recfmt#(8,24) cnan = get_cnan();
        if(inputs.issp) begin
          can1 = isNanBox(op1) ? op1 : {maxBound,cnan}; 
          can2 = isNanBox(op2) ? op2 : {maxBound,cnan}; 
          can3 = isNanBox(op3) ? op3 : {maxBound,cnan}; 
          Bit#(1) _a = truncate(op1>>32);
          Bit#(1) _b = truncate(op2>>32);
          fp_sign = _a ^ _b;
        end
        else begin
          can1 = op1;
          can2 = op2;
          can3 = op3;
          Bit#(1) _a = truncateLSB(op1);
          Bit#(1) _b = truncateLSB(op2);
          fp_sign = _a ^ _b;
        end
      end
      else begin
        can1 = op1;
        can2 = op2;
        can3 = op3;
        Bit#(1) _a = truncateLSB(op1);
        Bit#(1) _b = truncateLSB(op2);
        fp_sign = _a ^ _b;
      end

      `logLevel(fbox,1,$format("[%2d]FBOX: CAN inputs: can1:",hartid,fshow(can1)," can2:",fshow(can2),
        " can3:",fshow(can3)))
      Precision mode;
      if(dpfpu)
        mode = unpack(inputs.f7[0]);
      else
        mode = F;
      // fused ops
      if(inputs.opcode[2] == 0) begin 
        if(dpfpu && !inputs.issp) begin
          dpfma.ma_inputs(tuple5(inputs.opcode[1:0],can1,can2,can3,unpack(inputs.rm)));
          `logLevel(fbox,1,$format("[%2d]FBOX: Sending inputs for FMA[D]. ",hartid))
          ff_ordering.enq(DPFMA);
        end
        else begin
          spfma.ma_inputs(tuple5(inputs.opcode[1:0],truncate(can1),truncate(can2),truncate(can3),
                          unpack(inputs.rm)));
          `logLevel(fbox,1,$format("[%2d]FBOX: Sending inputs for FMA[F].",hartid))
          ff_ordering.enq(SPFMA);
        end
      end
      else if(inputs.opcode[2] == 1 && (inputs.f7[6:1] == `FADDS_f7 || inputs.f7[6:1]==`FSUBS_f7))
      begin
        if(dpfpu && !inputs.issp) begin
          Recfmt#(expwidth,sigwidth) _1 = get_1();
          dpfma.ma_inputs(tuple5(inputs.f7[3:2],can1,_1,can2,unpack(inputs.rm)));
          `logLevel(fbox,1,$format("[%2d]FBOX: Sending inputs for FADD/SUB[D].",hartid))
          ff_ordering.enq(DPFMA);
        end
        else begin
          Recfmt#(8,24) _1 = get_1();
          spfma.ma_inputs(tuple5(inputs.f7[3:2],truncate(can1),_1,truncate(can2),unpack(inputs.rm)));
          `logLevel(fbox,1,$format("[%2d]FBOX: Sending inputs for FADD/SUB[F].",hartid))
          ff_ordering.enq(SPFMA);
        end
      end
      else if(inputs.opcode[2] == 1 && (inputs.f7[6:1] == `FMULS_f7)) begin
        if(dpfpu && !inputs.issp) begin
          dpfma.ma_inputs(tuple5(0,can1,can2,resizeLSB(fp_sign),unpack(inputs.rm)));
          `logLevel(fbox,1,$format("[%2d]FBOX: Sending inputs for FMUL[D].",hartid))
          ff_ordering.enq(DPFMA);
        end
        else begin
          spfma.ma_inputs(tuple5(0,truncate(can1),truncate(can2),resizeLSB(fp_sign),unpack(inputs.rm)));
          `logLevel(fbox,1,$format("[%2d]FBOX: Sending inputs for FMUL[F].",hartid))
          ff_ordering.enq(SPFMA);
        end
      end
      else if( inputs.rm == 0 && inputs.opcode[2]==1 && 
                (inputs.f7[6:1] == `FMV_S_X_f7 || inputs.f7[6:1] == `FMV_X_S_f7))begin
          `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result for FMV.",hartid))
          FBoxOut_recfn#(xlen,expwidth,sigwidth) _o = ?;
          _o.fbox_flags = 0;

          // FMV.X.W
          if(inputs.f7[3] == 0) begin
            Recfmt#(expwidth,sigwidth) in = resize(inputs.op1);
            Bit#(flen) out = (cvt_fmv) ? to_ieee(in):resize(in);
            if(dpfpu && lv_xlen == 64 && inputs.f7[0] == 0) begin
              Bit#(32) _sp_out = resize(out);
              _o.fbox_result = signExtend(_sp_out);
            end
            else begin
              _o.fbox_result = resize(out);
            end
          end
          // FMV.W.X
          if(inputs.f7[3] == 1) begin
            IEEE#(expwidth,sigwidth) in;
            if(inputs.f7[0] == 0 && dpfpu && lv_xlen == 64) begin
              Bit#(32) _temp = resize(inputs.op1);
              Bit#(64) _k = {maxBound,_temp};
              in = resize(_k);
            end
            else begin
              in = resize(inputs.op1);
            end
            Recfmt#(expwidth,sigwidth) out = (cvt_fmv)? to_recfn(in):resize(in);
            _o.fbox_result = resize(out);
          end
          ff_result.enq(_o);
          ff_ordering.enq(SINGLECYCLE);
      end
      else if(inputs.opcode[2] == 1 && inputs.f7[6:1] == `FSGNJN_f7) begin
        `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result for FSJ*.",hartid))
        Recfmt#(expwidth,sigwidth) _r = fsgnj_recfn(can1,can2,mode,truncate(inputs.rm));
        FBoxOut_recfn#(xlen,expwidth,sigwidth) _o;
        _o.fbox_flags = 0;
        _o.fbox_result = resize(_r);
        ff_result.enq(_o);
        ff_ordering.enq(SINGLECYCLE);
      end
      else if(inputs.opcode[2]==1 && inputs.f7[6:1] == `FCLASS_f7 && inputs.rm == 1) begin
        `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result for FCLASS.",hartid))
        
        FBoxOut_recfn#(xlen,expwidth,sigwidth) _o;
        _o.fbox_result = fclass_recfn(can1,mode);
        _o.fbox_flags = 0;
        ff_result.enq(_o);
        ff_ordering.enq(SINGLECYCLE);
      end
      else if(inputs.opcode[2] == 1 && inputs.f7[6:1] == `FCMP_f7) begin
        Bit#(1) signalling = pack(!(inputs.rm == 2));
        if(dpfpu && !inputs.issp) begin
          `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result for FCMP[D].",hartid))
          dpcmp.request(can1,can2,signalling);
          FBoxOut_recfn#(xlen,expwidth,sigwidth) _r;
          Bit#(1) res = 0;
          case(inputs.rm) matches
            0: res = dpcmp.lt | dpcmp.eq;
            1: res = dpcmp.lt;
            2: res = dpcmp.eq;
          endcase
          _r.fbox_flags = dpcmp.exceptionFlags;
          _r.fbox_result = resize((dpcmp.unordered==1)?1'b0:res);
          ff_result.enq(_r);
          ff_ordering.enq(SINGLECYCLE);
        end
        else begin
          `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result for FCMP[F].",hartid))
          spcmp.request(truncate(can1),truncate(can2),signalling);
          FBoxOut_recfn#(xlen,expwidth,sigwidth) _r;
          Bit#(1) res = 0;
          case(inputs.rm) matches
            0: res = spcmp.lt | spcmp.eq;
            1: res = spcmp.lt;
            2: res = spcmp.eq;
          endcase
          _r.fbox_flags = spcmp.exceptionFlags;
          _r.fbox_result = resize((spcmp.unordered==1)?1'b0:res);
          ff_result.enq(_r);
          ff_ordering.enq(SINGLECYCLE);
        end
      end
      else if(inputs.opcode[2] == 1 && (inputs.f7[6:1] == `FDIV_f7 || inputs.f7[6:1] == `FSQRT_f7))
        begin
        if(dpfpu && inputs.f7[0] == 1) begin
          `logLevel(fbox,1,$format("[%2d]FBOX: Sending inputs to FDIV/FSQRT[D]. 1:",hartid,
            fshow(can1)," 2:",fshow(can2)))
          dpdivsqrt.request(1'b1,inputs.f7[5],can1,can2,inputs.rm);
          dpdivo_rdy[0] <= False;
          dpdiv_rdy <= False;
          ff_ordering.enq(DPDIVSQRT);
        end
        else begin
          `logLevel(fbox,1,$format("[%2d]FBOX: Sending inputs to FDIV/FSQRT[F].",hartid))
          spdivsqrt.request(1'b1,inputs.f7[5],truncate(can1),truncate(can2),inputs.rm);
          spdivo_rdy[0] <= False;
          spdiv_rdy <= False;
          ff_ordering.enq(SPDIVSQRT);
        end
      end
      else if(inputs.opcode[2] == 1 && inputs.f7[6:1] == `FMAX_f7) begin
        Bit#(1)  min_max = truncate(inputs.rm);
        `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result for FMIN(0)/FMAX(1): ",hartid,fshow(min_max)))
        let _r = fminmax_recfn(can1,can2,mode,min_max);
        FBoxOut_recfn#(xlen,expwidth,sigwidth) _o;
        _o.fbox_flags = tpl_2(_r);
        _o.fbox_result = resize(tpl_1(_r));
        ff_result.enq(_o);
        ff_ordering.enq(SINGLECYCLE);
      end
      else if(inputs.opcode[2] == 1 && (inputs.f7[6:1] == `FCVT_F2I_f7 || 
            inputs.f7[6:1] == `FCVT_I2F_f7)) begin
        Bit#(1) lv_signed = ~inputs.imm[0];
        Config cfg = ?;
        if(inputs.f7[0] == 0 && inputs.imm[1] == 0)
          cfg = RV32F;
        if(inputs.f7[0] == 0 && inputs.imm[1] == 1 && lv_xlen == 64)
          cfg = RV64F;
        if(inputs.f7[0] == 1 && inputs.imm[1] == 0 && dpfpu)
          cfg = RV32D;
        if(inputs.f7[0] == 1 && inputs.imm[1] == 1 && dpfpu && lv_xlen == 64)
          cfg = RV64D;
        `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result for FCVT Int Ops:",hartid,fshow(cfg)," ."))
        Bit#(xlen) _inp = truncate(inputs.op1);
        if(inputs.f7[3] == 1) begin
          Tuple2#(Recfmt#(expwidth,sigwidth),Bit#(5)) x <- 
                                  in_to_recfn(lv_signed,_inp,unpack(inputs.rm),cfg);
          FBoxOut_recfn#(xlen,expwidth,sigwidth) _o;
          _o.fbox_flags = tpl_2(x);
          _o.fbox_result = resize(tpl_1(x));
          ff_result.enq(_o);
          ff_ordering.enq(SINGLECYCLE);
        end
        else begin
          Tuple2#(Bit#(xlen),Bit#(3)) x <- recfn_to_in(op1,inputs.rm,cfg,lv_signed);
          FBoxOut_recfn#(xlen,expwidth,sigwidth) _o;
          let _flags = tpl_2(x);
          _o.fbox_flags = {_flags[2],1'b0,_flags[1],1'b0,_flags[0]};
          _o.fbox_result = resize(tpl_1(x));
          ff_result.enq(_o);
          ff_ordering.enq(SINGLECYCLE);
        end
      end
      else if(inputs.opcode[2] == 1 && dpfpu && (inputs.f7[6:1] == `FCVT_S_D_f7)) begin
        `logLevel(fbox,1,$format("[%2d]FBOX: Enqueuing result for FCVT SD Ops.",hartid))
        FBoxOut_recfn#(xlen,expwidth,sigwidth) _o;
        if(inputs.imm[0] == 1 && inputs.f7[0] ==0) begin
          dptosp.request(1,op1,inputs.rm);
          _o.fbox_flags = dptosp.exceptionFlags;
          _o.fbox_result = resize_max(dptosp.out);
          ff_result.enq(_o);
          ff_ordering.enq(SINGLECYCLE);
        end
        else begin
          sptodp.request(1,truncate(can1),inputs.rm);
          Recfmt#(expwidth,sigwidth) _temp = fn_sanitise_nan(sptodp.out);
          _o.fbox_flags = sptodp.exceptionFlags;
          _o.fbox_result = resize(_temp);
          ff_result.enq(_o);
          ff_ordering.enq(SINGLECYCLE);
        end
      end
    endmethod

    method mv_ready = lv_ready;
    
    method tx_output = tx_fbox_out.e;
  endmodule

endpackage
