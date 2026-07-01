/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved. See LICENSE.incore for more details.
  Created On:  Thu Feb 10, 2022 17:49:42 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks
 */

package mulAddRec;

`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import FloatingPoint :: * ;
  import PAClib        :: * ;

  `include "fconsts.defines"

  
  interface Ifc_mulAddRecFNToRaw_preMul#(numeric type expWidth,
    numeric type sigWidth);
    (*always_enabled*)
    method Bit#(sigWidth) mulAddA();
    (*always_enabled*)
    method Bit#(sigWidth) mulAddB();
    (*always_enabled*)
    method Bit#(TMul#(sigWidth,2)) mulAddC();
    (*always_enabled*)
    method Bit#(6) intermed_compactState();
    (*always_enabled*)
    method Bit#(TLog#(TAdd#(sigWidth,1))) intermed_CDom_CAlignDist();
    (*always_enabled*)
    method Bit#(TAdd#(expWidth,2)) intermed_sExp();
    (*always_enabled*)
    method Bit#(TAdd#(sigWidth,2)) intermed_highAlignedSigC();
    (*always_ready*)
    method Action request(Bit#(`control) control,Bit#(2) op,Bit#(TAdd#(1,TAdd#(sigWidth,expWidth))) a,Bit#(TAdd#(1,TAdd#(sigWidth,expWidth))) b,Bit#(TAdd#(1,TAdd#(sigWidth,expWidth))) c,Bit#(3) roundingMode);
  endinterface: Ifc_mulAddRecFNToRaw_preMul

  import "BVI" mulAddRecFNToRaw_preMul=
  module mk_mulAddRecFNToRaw_preMul(Ifc_mulAddRecFNToRaw_preMul#(expWidth,sigWidth));
    default_clock clk();
    default_reset rstn();
    
    parameter expWidth = valueOf(expWidth);
    parameter sigWidth = valueOf(sigWidth);
    method mulAddA mulAddA()  clocked_by(clk) reset_by(rstn);
    method mulAddB mulAddB() ;
    method mulAddC mulAddC() ;
    method intermed_compactState intermed_compactState() ;
    method intermed_CDom_CAlignDist intermed_CDom_CAlignDist() ;
    method intermed_sExp intermed_sExp() ;
    method intermed_highAlignedSigC intermed_highAlignedSigC() ;
    method request(control,op,a,b,c,roundingMode)  enable((*inhigh*) en_request);
    schedule (mulAddA,mulAddB,mulAddC,intermed_compactState,intermed_sExp,intermed_highAlignedSigC,intermed_CDom_CAlignDist,request) CF (mulAddA,mulAddB,mulAddC,intermed_compactState,intermed_sExp,intermed_highAlignedSigC,intermed_CDom_CAlignDist);
  endmodule: mk_mulAddRecFNToRaw_preMul

  
  interface Ifc_mulAddRecFNToRaw_postMul#(numeric type expWidth,
    numeric type sigWidth);
    (*always_ready*)
    method Action request(Bit#(6) intermed_compactState,Bit#(TAdd#(expWidth,2)) intermed_sExp,Bit#(TLog#(TAdd#(sigWidth,1))) intermed_CDom_CAlignDist,Bit#(TAdd#(sigWidth,2)) intermed_highAlignedSigC,Bit#(TAdd#(TMul#(sigWidth,2),1)) mulAddResult,Bit#(3) roundingMode);
    (*always_enabled*)
    method Bit#(1) invalidExc();
    (*always_enabled*)
    method Bit#(1) out_isNaN();
    (*always_enabled*)
    method Bit#(1) out_isInf();
    (*always_enabled*)
    method Bit#(1) out_isZero();
    (*always_enabled*)
    method Bit#(1) out_sign();
    (*always_enabled*)
    method Bit#(TAdd#(expWidth,2)) out_sExp();
    (*always_enabled*)
    method Bit#(TAdd#(sigWidth,3)) out_sig();
  endinterface: Ifc_mulAddRecFNToRaw_postMul

  import "BVI" mulAddRecFNToRaw_postMul=
  module mk_mulAddRecFNToRaw_postMul(Ifc_mulAddRecFNToRaw_postMul#(expWidth,sigWidth));
    default_clock clk();
    default_reset rstn();
    
    parameter expWidth = valueOf(expWidth);
    parameter sigWidth = valueOf(sigWidth);
    method request(intermed_compactState,intermed_sExp,intermed_CDom_CAlignDist,intermed_highAlignedSigC,mulAddResult,roundingMode)  enable((*inhigh*) en_request);
    method invalidExc invalidExc() ;
    method out_isNaN out_isNaN() ;
    method out_isInf out_isInf() ;
    method out_isZero out_isZero() ;
    method out_sign out_sign() ;
    method out_sExp out_sExp() ;
    method out_sig out_sig() ;
    schedule (invalidExc,out_isNaN,out_isInf,out_isZero,out_sign,out_sExp,out_sig,request) CF (invalidExc,out_isNaN,out_isInf,out_isZero,out_sign,out_sExp,out_sig);
    path(intermed_compactState,invalidExc);
    path(intermed_compactState,out_isNaN);
    path(intermed_compactState,out_isInf);
    path(intermed_compactState,out_isZero);
    path(intermed_compactState,out_sign);
    path(intermed_compactState,out_sExp);
    path(intermed_compactState,out_sig);
    path(intermed_sExp,invalidExc);
    path(intermed_sExp,out_isNaN);
    path(intermed_sExp,out_isInf);
    path(intermed_sExp,out_isZero);
    path(intermed_sExp,out_sign);
    path(intermed_sExp,out_sExp);
    path(intermed_sExp,out_sig);
    path(intermed_CDom_CAlignDist,invalidExc);
    path(intermed_CDom_CAlignDist,out_isNaN);
    path(intermed_CDom_CAlignDist,out_isInf);
    path(intermed_CDom_CAlignDist,out_isZero);
    path(intermed_CDom_CAlignDist,out_sign);
    path(intermed_CDom_CAlignDist,out_sExp);
    path(intermed_CDom_CAlignDist,out_sig);
    path(intermed_highAlignedSigC,invalidExc);
    path(intermed_highAlignedSigC,out_isNaN);
    path(intermed_highAlignedSigC,out_isInf);
    path(intermed_highAlignedSigC,out_isZero);
    path(intermed_highAlignedSigC,out_sign);
    path(intermed_highAlignedSigC,out_sExp);
    path(intermed_highAlignedSigC,out_sig);
    path(mulAddResult,invalidExc);
    path(mulAddResult,out_isNaN);
    path(mulAddResult,out_isInf);
    path(mulAddResult,out_isZero);
    path(mulAddResult,out_sign);
    path(mulAddResult,out_sExp);
    path(mulAddResult,out_sig);
    path(roundingMode,invalidExc);
    path(roundingMode,out_isNaN);
    path(roundingMode,out_isInf);
    path(roundingMode,out_isZero);
    path(roundingMode,out_sign);
    path(roundingMode,out_sExp);
    path(roundingMode,out_sig);
  endmodule: mk_mulAddRecFNToRaw_postMul

  interface Ifc_MAC#(numeric type sigWidth);
    (*always_ready,always_enabled*)
    method Bit#(TAdd#(TMul#(sigWidth,2),1)) request(
    Bit#(sigWidth) mulAddA,
    Bit#(sigWidth) mulAddB,
    Bit#(TMul#(sigWidth,2)) mulAddC);
  endinterface

  module mk_MAC(Ifc_MAC#(sigWidth)) provisos(
    Add#(1,TMul#(sigWidth,2),sz_out),
    Add#(a__, sigWidth, sz_out),
    Add#(b__, TAdd#(sigWidth, sigWidth), sz_out)
  );
    method Bit#(sz_out) request(
      Bit#(sigWidth) mulAddA,
      Bit#(sigWidth) mulAddB,
      Bit#(TMul#(sigWidth,2)) mulAddC
      );
      
      Bit#(sz_out) res = zeroExtend(primMul(mulAddA,mulAddB)) + zeroExtend(mulAddC); 
      return res;
    endmethod
  endmodule

endpackage: mulAddRec
