/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved. See LICENSE.incore for more details.
  Created On:  Mon Feb 14, 2022 16:27:00 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks
*/
package instances;

`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import retimed_fma :: * ;
  import mulAddRec   :: * ;
  import recFN       :: * ;
  import PAClib      :: * ;
  import retiming    :: * ;
  import fma         :: * ;
  import Vector      :: * ;

  /* `include "instances.defines" */
  /* typedef Bit#(TAdd#(1,TAdd#(`sigwidth,`expwidth))) Recfmt#(`expwidth,`sigwidth); */

  (*synthesize*)
  module mk_inst_fn_itorec(Ifc_retimed#(Tuple4#(Bit#(1),Bit#(2),Bit#(`xlen),Bit#(3)),
    Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))));
    
    /* Ifc_iNToRecFN#(`expwidth,`sigwidth,`xlen) mod <- mk_iNToRecFN; */
    RWire#(Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))) wr_res <- mkRWire;

    let ifc_in = interface Ifc_retime
      method Action ma_request(Tuple4#(Bit#(1),Bit#(2),Bit#(`xlen),Bit#(3)) in);
        /* mod.request(tpl_1(in),tpl_2(in),tpl_3(in),tpl_4(in)); */
        let x <- in_to_recfn(tpl_1(in),tpl_3(in),unpack(tpl_4(in)),unpack(tpl_2(in)));
        wr_res.wset(x);
      endmethod
      method ActionValue#(Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))) mv_response;
        /* return tuple2(mod.out(),mod.exceptionFlags()); */
        return fromMaybe(?,wr_res.wget());
      endmethod    
    endinterface;

    let ifc();
    mkretimed#(ifc_in,`in,`out) _temp(ifc());
    return ifc;
  endmodule

  (*synthesize*)
  module
  mk_ftod_inst(Ifc_retimed#(Tuple3#(Bit#(1),Recfmt#(8,24),Bit#(3)),Tuple2#(Recfmt#(11,53),Bit#(5))));

    Ifc_recFNToRecFN#(8,24,11,53) mod <- mk_recFNToRecFN;


    Ifc_retime#(Tuple3#(Bit#(1),Recfmt#(8,24),Bit#(3)),Tuple2#(Recfmt#(11,53),Bit#(5))) ifc_in = 
      interface Ifc_retime
        
        method Action ma_request( Tuple3#(Bit#(1),Recfmt#(8,24),Bit#(3)) x);
          mod.request(tpl_1(x),tpl_2(x),tpl_3(x));
        endmethod
        method ActionValue#(Tuple2#(Recfmt#(11,53),Bit#(5))) mv_response;
          return tuple2(mod.out(),mod.exceptionFlags());
        endmethod
      endinterface;


    let ifc();
    mkretimed#(ifc_in,`in,`out) _temp(ifc());
    return ifc();
  endmodule


  (*synthesize*)
  module
  mk_dtof_inst(Ifc_retimed#(Tuple3#(Bit#(1),Recfmt#(11,53),Bit#(3)),Tuple2#(Recfmt#(8,24),Bit#(5))));

    Ifc_recFNToRecFN#(11,53,8,24) mod <- mk_recFNToRecFN;


    Ifc_retime#(Tuple3#(Bit#(1),Recfmt#(11,53),Bit#(3)),Tuple2#(Recfmt#(8,24),Bit#(5))) ifc_in = 
      interface Ifc_retime
        
        method Action ma_request( Tuple3#(Bit#(1),Recfmt#(11,53),Bit#(3)) x);
          mod.request(tpl_1(x),tpl_2(x),tpl_3(x));
        endmethod
        method ActionValue#(Tuple2#(Recfmt#(8,24),Bit#(5))) mv_response;
          return tuple2(mod.out(),mod.exceptionFlags());
        endmethod
      endinterface;


    let ifc();
    mkretimed#(ifc_in,`in,`out) _temp(ifc());
    return ifc();
  endmodule

  (*synthesize*)
  module mk_inst_ftorec(Ifc_retimed#(Bit#(TAdd#(`expwidth,`sigwidth)),Recfmt#(`expwidth,`sigwidth)));

    Ifc_fNToRecFN#(`expwidth,`sigwidth) mod <- mk_fNToRecFN;

    let ifc_in = interface Ifc_retime
      method Action ma_request(Bit#(TAdd#(`expwidth,`sigwidth)) in);
        mod.request(in);
      endmethod
      method ActionValue#(Recfmt#(`expwidth,`sigwidth)) mv_response;
        return mod.out();
      endmethod
    endinterface;

    let ifc();
    mkretimed#(ifc_in,`in,`out) _temp(ifc());
    return ifc;
  endmodule

  (*synthesize*)
  module mk_inst_rectof(Ifc_retimed#(Recfmt#(`expwidth,`sigwidth),Bit#(TAdd#(`expwidth,`sigwidth))));
    Ifc_recFNToFN#(`expwidth,`sigwidth) mod <- mk_recFNToFN;

    let ifc_in = interface Ifc_retime
      method Action ma_request(Recfmt#(`expwidth,`sigwidth) in);
        mod.request(in);
      endmethod
      method ActionValue#(Bit#(TAdd#(`expwidth,`sigwidth))) mv_response;
        return mod.out();
      endmethod
    endinterface;

    let ifc();
    mkretimed#(ifc_in,`in,`out) _temp(ifc());
    return ifc;  endmodule

  (*synthesize*)
  module mk_inst_rectoi(Ifc_retimed#(Tuple4#(Bit#(1),Recfmt#(`expwidth,`sigwidth),Bit#(3),Bit#(1)),
    Tuple2#(Bit#(`xlen),Bit#(3))));
    Ifc_recFNToIN#(`expwidth,`sigwidth,`xlen) mod <- mk_recFNToIN;
    let ifc_in = interface Ifc_retime
      method Action ma_request(Tuple4#(Bit#(1),Recfmt#(`expwidth,`sigwidth),Bit#(3),Bit#(1)) in);
        mod.request(tpl_1(in),tpl_2(in),tpl_3(in),tpl_4(in));
      endmethod
      method ActionValue#(Tuple2#(Bit#(`xlen),Bit#(3))) mv_response;
        return tuple2(mod.out(),mod.intExceptionFlags());
      endmethod
    endinterface;

    let ifc();
    mkretimed#(ifc_in,`in,`out) _temp(ifc());
    return ifc; 
  endmodule

  (*synthesize*)
  module mk_inst_itorec(Ifc_retimed#(Tuple4#(Bit#(1),Bit#(1),Bit#(`xlen),Bit#(3)),
    Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))));
    
    Ifc_iNToRecFN#(`expwidth,`sigwidth,`xlen) mod <- mk_iNToRecFN;

    let ifc_in = interface Ifc_retime
      method Action ma_request(Tuple4#(Bit#(1),Bit#(1),Bit#(`xlen),Bit#(3)) in);
        mod.request(tpl_1(in),tpl_2(in),tpl_3(in),tpl_4(in));
      endmethod
      method ActionValue#(Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))) mv_response;
        return tuple2(mod.out(),mod.exceptionFlags());
      endmethod    
    endinterface;

    let ifc();
    mkretimed#(ifc_in,`in,`out) _temp(ifc());
    return ifc;
  endmodule

  module mk_wrap_fma(Ifc_retime#(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)),Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))));

    Ifc_rec_fma#(`expwidth,`sigwidth) fma <- mk_rec_fma;

    method Action ma_request(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)) x);
      fma.ma_inputs(tpl_1(x),tpl_2(x),tpl_3(x),tpl_4(x),tpl_5(x));
    endmethod

    method ActionValue#(Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))) mv_response;
      let out <- fma.mv_output;
      return out;
    endmethod
  endmodule

  (*synthesize*)
  module 
  mk_test(Ifc_fma#(`expwidth,`sigwidth));
   ModConfig cfg[4] = {
    ModConfig{name: Pre,in: 2, out: 2},
    ModConfig{name: Mac, in: 0, out: 2},
    ModConfig{name: Post, in: 0, out: 2},
    ModConfig{name: Round, in: 0, out: 2}
   };
   Ifc_fma#(`expwidth,`sigwidth) ifc <- mkfma(arrayToVector(cfg));
   return ifc;
  endmodule

  (*synthesize*)
  module
  mk_inst(Ifc_retimed#(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)),Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))));
    Ifc_retime#(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)),Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))) mod_ifc <-
      mk_wrap_fma;
    let ifc();
    mkretimed#(mod_ifc,`in,`out) _temp(ifc());
    return ifc;
  endmodule

  (*synthesize*)
  module mk_inst_pre(Ifc_retimed#(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)),
    Tuple7#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(`sigwidth,2)),Bit#(6),
      Bit#(TLog#(TAdd#(`sigwidth,1))), Bit#(TAdd#(`expwidth,2)), Bit#(TAdd#(`sigwidth,2)))));
  
    Ifc_mulAddRecFNToRaw_preMul#(`expwidth,`sigwidth) premul <- mk_mulAddRecFNToRaw_preMul();

    Ifc_retime#(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)),
    Tuple7#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(`sigwidth,2)),Bit#(6),
      Bit#(TLog#(TAdd#(`sigwidth,1))), Bit#(TAdd#(`expwidth,2)), Bit#(TAdd#(`sigwidth,2)))) in_ifc =
      interface Ifc_retime
        method Action ma_request( Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)) x);
          premul.request(1,tpl_1(x),tpl_2(x),tpl_3(x),tpl_4(x),tpl_5(x));
        endmethod
        method ActionValue#(Tuple7#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(`sigwidth,2)),Bit#(6),
            Bit#(TLog#(TAdd#(`sigwidth,1))), Bit#(TAdd#(`expwidth,2)), Bit#(TAdd#(`sigwidth,2))))
            mv_response;
          return tuple7(
            premul.mulAddA,
            premul.mulAddB,
            premul.mulAddC,
            premul.intermed_compactState,
            premul.intermed_CDom_CAlignDist,
            premul.intermed_sExp,
            premul.intermed_highAlignedSigC);
        endmethod
      endinterface;
    let ifc();
    mkretimed#(in_ifc,`in,`out) _temp(ifc());
    return ifc;
  endmodule

  (*synthesize*)
  module mk_inst_pre_mac(Ifc_retimed#(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)),
    Tuple5#(Bit#(6),Bit#(TLog#(TAdd#(`sigwidth,1))), Bit#(TAdd#(`expwidth,2)), 
      Bit#(TAdd#(`sigwidth,2)),Bit#(TAdd#(1,TMul#(`sigwidth,2))))));
  
    Ifc_mulAddRecFNToRaw_preMul#(`expwidth,`sigwidth) premul <- mk_mulAddRecFNToRaw_preMul();

    Ifc_MAC#(`sigwidth) mac <- mk_MAC();

    RWire#(Bit#(TAdd#(1,TMul#(`sigwidth,2)))) wr_res <- mkUnsafeRWire();

    Ifc_retime#(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)),
      Tuple5#(Bit#(6),Bit#(TLog#(TAdd#(`sigwidth,1))), Bit#(TAdd#(`expwidth,2)), 
      Bit#(TAdd#(`sigwidth,2)),Bit#(TAdd#(1,TMul#(`sigwidth,2))))) in_ifc =
      interface Ifc_retime
        method Action ma_request( Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)) x);
          premul.request(1,tpl_1(x),tpl_2(x),tpl_3(x),tpl_4(x),tpl_5(x));
          let res = mac.request(premul.mulAddA(),premul.mulAddB(),premul.mulAddC());
          wr_res.wset(res);
        endmethod
        method ActionValue#(Tuple5#(Bit#(6),Bit#(TLog#(TAdd#(`sigwidth,1))), Bit#(TAdd#(`expwidth,2)), 
      Bit#(TAdd#(`sigwidth,2)),Bit#(TAdd#(1,TMul#(`sigwidth,2)))))
            mv_response;
          return tuple5(
            premul.intermed_compactState,
            premul.intermed_CDom_CAlignDist,
            premul.intermed_sExp,
            premul.intermed_highAlignedSigC,
            fromMaybe(?,wr_res.wget()));
        endmethod
      endinterface;
    let ifc();
    mkretimed#(in_ifc,`in,`out) _temp(ifc());
    return ifc;
  endmodule

  /* interface Ifc_pipe_retimed#(type a, type b); */
  /*   method Action ma_inputs (a x); */
  /*   interface PipeOut#(b) pout; */
  /* endinterface */

  /* (*synthesize*) */
  /* module mk_inst_pre_pipe(Ifc_pipe_retimed#(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)), */
  /*   Tuple7#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(`sigwidth,2)),Bit#(6), */
  /*     Bit#(TLog#(TAdd#(`sigwidth,1))), Bit#(TAdd#(`expwidth,2)), Bit#(TAdd#(`sigwidth,2))))); */
  
  /*   Ifc_mulAddRecFNToRaw_preMul#(`expwidth,`sigwidth) premul <- mk_mulAddRecFNToRaw_preMul(); */

  /*   RWire#(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3))) wr_inputs <- mkRWire(); */
  /*   Ifc_retime#(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)), */
  /*   Tuple7#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(`sigwidth,2)),Bit#(6), */
  /*     Bit#(TLog#(TAdd#(`sigwidth,1))), Bit#(TAdd#(`expwidth,2)), Bit#(TAdd#(`sigwidth,2)))) in_ifc = */
  /*     interface Ifc_retime */
  /*       method Action ma_request( Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)) x); */
  /*         premul.request(1,tpl_1(x),tpl_2(x),tpl_3(x),tpl_4(x),tpl_5(x)); */
  /*       endmethod */
  /*       method ActionValue#(Tuple7#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(`sigwidth,2)),Bit#(6), */
  /*           Bit#(TLog#(TAdd#(`sigwidth,1))), Bit#(TAdd#(`expwidth,2)), Bit#(TAdd#(`sigwidth,2)))) */
  /*           mv_response; */
  /*         return tuple7( */
  /*           premul.mulAddA, */
  /*           premul.mulAddB, */
  /*           premul.mulAddC, */
  /*           premul.intermed_compactState, */
  /*           premul.intermed_CDom_CAlignDist, */
  /*           premul.intermed_sExp, */
  /*           premul.intermed_highAlignedSigC); */
  /*       endmethod */
  /*     endinterface; */
  /*   PipeOut#( Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3))) pin = interface PipeOut */
  /*     method first = fromMaybe(?,wr_inputs.wget()); */
  /*     method notEmpty = isValid(wr_inputs.wget()); */
  /*     method Action deq; */
  /*       noAction; */
  /*     endmethod */
  /*   endinterface; */
  /*   let ifc(); */
  /*   mkretimed_pipe#(in_ifc,3,3,pin) _temp(ifc()); */

  /*     method Action ma_inputs(Tuple5#(Bit#(2),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Recfmt#(`expwidth,`sigwidth),Bit#(3)) x); */
  /*       wr_inputs.wset(x); */
  /*     endmethod */
  /*     interface pout = ifc; */

  /* endmodule */

  (*synthesize*)
  module mk_inst_post_round(Ifc_retimed#(Tuple6#(Bit#(6),Bit#(TAdd#(`expwidth,2)),
    Bit#(TLog#(TAdd#(`sigwidth,1))),Bit#(TAdd#(`sigwidth,2)),Bit#(TAdd#(TMul#(`sigwidth,2),1)),Bit#(3)),
    Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))));

    Ifc_mulAddRecFNToRaw_postMul#(`expwidth,`sigwidth) postmul <- mk_mulAddRecFNToRaw_postMul();
    Ifc_roundRawFNToRecFN#(`expwidth,`sigwidth,0) round <- mk_roundRawFNToRecFN();   

    Ifc_retime#(Tuple6#(Bit#(6),Bit#(TAdd#(`expwidth,2)),
      Bit#(TLog#(TAdd#(`sigwidth,1))),Bit#(TAdd#(`sigwidth,2)),Bit#(TAdd#(TMul#(`sigwidth,2),1)),Bit#(3)),
      Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))) in_ifc = interface Ifc_retime

      method Action ma_request(Tuple6#(Bit#(6),Bit#(TAdd#(`expwidth,2)),
        Bit#(TLog#(TAdd#(`sigwidth,1))),Bit#(TAdd#(`sigwidth,2)),
        Bit#(TAdd#(TMul#(`sigwidth,2),1)),Bit#(3)) x);
        postmul.request(tpl_1(x),tpl_2(x),tpl_3(x),tpl_4(x),tpl_5(x),tpl_6(x));
        round.request(1, postmul.invalidExc(), 1'b0, postmul.out_isNaN(), postmul.out_isInf(),
          postmul.out_isZero(), postmul.out_sign(), postmul.out_sExp(), postmul.out_sig(), tpl_6(x)); 
      endmethod
      method ActionValue#(Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))) mv_response;
        return tuple2(round.out(), round.exceptionFlags());
      endmethod
    endinterface;

    let ifc();
    mkretimed#(in_ifc,`in,`out) _temp(ifc());
    return ifc;
  endmodule

  (*synthesize*)
  module mk_inst_post(Ifc_retimed#(Tuple6#(Bit#(6),Bit#(TAdd#(`expwidth,2)),
    Bit#(TLog#(TAdd#(`sigwidth,1))),Bit#(TAdd#(`sigwidth,2)),Bit#(TAdd#(TMul#(`sigwidth,2),1)),Bit#(3)),
    Tuple7#(Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(TAdd#(`expwidth,2)),
    Bit#(TAdd#(`sigwidth,3)))));

    Ifc_mulAddRecFNToRaw_postMul#(`expwidth,`sigwidth) postmul <- mk_mulAddRecFNToRaw_postMul();
    Ifc_roundRawFNToRecFN#(`expwidth,`sigwidth,0) round <- mk_roundRawFNToRecFN();   

    Ifc_retime#(Tuple6#(Bit#(6),Bit#(TAdd#(`expwidth,2)),
      Bit#(TLog#(TAdd#(`sigwidth,1))),Bit#(TAdd#(`sigwidth,2)),Bit#(TAdd#(TMul#(`sigwidth,2),1)),Bit#(3)),
      Tuple7#(Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(TAdd#(`expwidth,2)),
    Bit#(TAdd#(`sigwidth,3)))) in_ifc = interface Ifc_retime

      method Action ma_request(Tuple6#(Bit#(6),Bit#(TAdd#(`expwidth,2)),
        Bit#(TLog#(TAdd#(`sigwidth,1))),Bit#(TAdd#(`sigwidth,2)),
        Bit#(TAdd#(TMul#(`sigwidth,2),1)),Bit#(3)) x);
        postmul.request(tpl_1(x),tpl_2(x),tpl_3(x),tpl_4(x),tpl_5(x),tpl_6(x));
        round.request(1, postmul.invalidExc(), 1'b0, postmul.out_isNaN(), postmul.out_isInf(),
          postmul.out_isZero(), postmul.out_sign(), postmul.out_sExp(), postmul.out_sig(), tpl_6(x)); 
      endmethod
      method ActionValue#(Tuple7#(Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(TAdd#(`expwidth,2)),
    Bit#(TAdd#(`sigwidth,3)))) mv_response;
        return tuple7(postmul.invalidExc(), postmul.out_isNaN(), postmul.out_isInf(),
          postmul.out_isZero(), postmul.out_sign(), postmul.out_sExp(), postmul.out_sig());
      endmethod
    endinterface;

    let ifc();
    mkretimed#(in_ifc,`in,`out) _temp(ifc());
    return ifc;
  endmodule


  (*synthesize*)
  module
  mk_inst_mac_post(Ifc_retimed#(Tuple8#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(2,`sigwidth)),
    Bit#(6),Bit#(TAdd#(`expwidth,2)),Bit#(TLog#(TAdd#(`sigwidth,1))),Bit#(TAdd#(`sigwidth,2)),Bit#(3)),
    Tuple7#(Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(TAdd#(`expwidth,2)),
    Bit#(TAdd#(`sigwidth,3)))));

    Ifc_mulAddRecFNToRaw_postMul#(`expwidth,`sigwidth) postmul <- mk_mulAddRecFNToRaw_postMul();

    Ifc_MAC#(`sigwidth) mac <- mk_MAC();

    Ifc_retime#(Tuple8#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(2,`sigwidth)),
    Bit#(6),Bit#(TAdd#(`expwidth,2)),Bit#(TLog#(TAdd#(`sigwidth,1))),Bit#(TAdd#(`sigwidth,2)),Bit#(3)),
    Tuple7#(Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(TAdd#(`expwidth,2)),
    Bit#(TAdd#(`sigwidth,3)))) in_ifc = interface Ifc_retime

      method Action ma_request(Tuple8#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(2,`sigwidth)),
    Bit#(6),Bit#(TAdd#(`expwidth,2)),Bit#(TLog#(TAdd#(`sigwidth,1))),Bit#(TAdd#(`sigwidth,2)),Bit#(3)) x);
        let res = mac.request(tpl_1(x),tpl_2(x),tpl_3(x));
        postmul.request(tpl_4(x),tpl_5(x),tpl_6(x),tpl_7(x),res,tpl_8(x));
      endmethod
      method ActionValue#(Tuple7#(Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(TAdd#(`expwidth,2)),
    Bit#(TAdd#(`sigwidth,3)))) mv_response;
        return tuple7(postmul.invalidExc(), postmul.out_isNaN(), postmul.out_isInf(),
          postmul.out_isZero(), postmul.out_sign(), postmul.out_sExp(), postmul.out_sig());
      endmethod
    endinterface;

    let ifc();
    mkretimed#(in_ifc,`in,`out) _temp(ifc());
    return ifc;
  endmodule


  (*synthesize*)
  module mk_inst_round(Ifc_retimed#(Tuple8#(Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(TAdd#(`expwidth,2)),
    Bit#(TAdd#(`sigwidth,3)), Bit#(3) ),
    Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))));

    /* Ifc_mulAddRecFNToRaw_postMul#(`expwidth,`sigwidth) postmul <- mk_mulAddRecFNToRaw_postMul(); */
    Ifc_roundRawFNToRecFN#(`expwidth,`sigwidth,0) round <- mk_roundRawFNToRecFN();   

    Ifc_retime#(Tuple8#(Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(TAdd#(`expwidth,2)),
    Bit#(TAdd#(`sigwidth,3)), Bit#(3) ),
    Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))) in_ifc = interface Ifc_retime

      method Action ma_request(Tuple8#(Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(1),
    Bit#(TAdd#(`expwidth,2)),
    Bit#(TAdd#(`sigwidth,3)), Bit#(3) ) x);
        round.request(1, tpl_1(x), 1'b0, tpl_2(x),tpl_3(x),
          tpl_4(x), tpl_5(x), tpl_6(x), tpl_7(x), tpl_8(x)); 
      endmethod
      method ActionValue#(Tuple2#(Recfmt#(`expwidth,`sigwidth),Bit#(5))) mv_response;
        return tuple2(round.out(), round.exceptionFlags());
      endmethod
    endinterface;

    let ifc();
    mkretimed#(in_ifc,`in,`out) _temp(ifc());
    return ifc;
  endmodule


  (*synthesize*)
  module mk_inst_mac(Ifc_retimed#(Tuple3#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(2,`sigwidth))),
      Bit#(TAdd#(1,TMul#(`sigwidth,2)))));

    Ifc_MAC#(`sigwidth) mac <- mk_MAC();

    RWire#(Bit#(TAdd#(1,TMul#(`sigwidth,2)))) wr_res <- mkUnsafeRWire();

    Ifc_retime#(Tuple3#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(`sigwidth,2))),
      Bit#(TAdd#(1,TMul#(`sigwidth,2)))) in_ifc = interface Ifc_retime
      method Action ma_request(Tuple3#(Bit#(`sigwidth),Bit#(`sigwidth),Bit#(TMul#(`sigwidth,2))) x);
        let res = mac.request(tpl_1(x),tpl_2(x),tpl_3(x));
        wr_res.wset(res);
      endmethod
      method ActionValue#(Bit#(TAdd#(1,TMul#(`sigwidth,2)))) mv_response;
        return fromMaybe(?,wr_res.wget());
      endmethod
    endinterface;


    let ifc();
    mkretimed#(in_ifc,`in,`out) _temp(ifc());
    return ifc; 
  endmodule
  

/*   (*synthesize*) */
/*   module mk_fma_inst(Ifc_retimed_fma_1#( `expwidth,`sigwidth,2,1 )); */
/*     let ifc(); */
/*     mkretimed_fma _temp(ifc()); */
/*     return ifc; */
/*   endmodule */

/*   (*synthesize*) */
/*   module mk_fma_old_inst(Ifc_retimed_fma#( `expwidth,`sigwidth,4,1 )); */
/*     let ifc(); */
/*     mkretimed_fma_old _temp(ifc()); */
/*     return ifc; */
/*   endmodule */


/*   (*synthesize*) */
/*   module mk_premul_inst(Ifc_mulAddRecFNToRaw_preMul#(`expwidth,`sigwidth)); */
/*     let ifc(); */
/*     mk_mulAddRecFNToRaw_preMul _temp(ifc()); */
/*     return ifc; */
/*   endmodule */

/*   (*synthesize*) */
/*   module mk_postmul_inst(Ifc_mulAddRecFNToRaw_postMul#(`expwidth,`sigwidth)); */
/*     let ifc(); */
/*     mk_mulAddRecFNToRaw_postMul _temp(ifc()); */
/*     return ifc; */
/*   endmodule */

/*   (*synthesize*) */
/*   module mk_round_inst(Ifc_roundRawFNToRecFN#(`expwidth,`sigwidth,0)); */
/*     let ifc(); */
/*     mk_roundRawFNToRecFN _temp(ifc()); */
/*     return ifc; */
/*   endmodule */

/*   (*synthesize*) */
/*   module mk_mac_inst(Ifc_MAC#(`sigwidth)); */
/*     let ifc(); */
/*     mk_MAC _temp(ifc()); */
/*     return ifc(); */
/*   endmodule */

  /* interface Ifc_test#(numeric type a); */
  /*   method Bit#(TLog#(a)) clz(Bit#(a) a); */
  /* endinterface */
  
  /* (*synthesize*) */
  /* module mk_clz(Ifc_test#(52)); */
  /*   method Bit#(TLog#(52)) clz(Bit#(52) a); */
  /*     return pack(zeroExtend(countZerosMSB(a))); */
  /*   endmethod */
  /* endmodule */

  /* import "BVI" countLeadingZeros = */ 
  /* module mk_v_clz(Ifc_test#(52)); */
  /*   parameter inWidth = 52; */
  /*   parameter countWidth = 6; */

  /*   default_clock no_clock; */
  /*   default_reset no_reset; */

  /*   method count clz(in); */
  /* endmodule */

  /* (*synthesize*) */
  /* module mk_clz_v(Ifc_test#(52)); */
  /*   let ifc(); */
  /*   mk_v_clz _temp(ifc()); */
  /*   return ifc; */
  /* endmodule */

  /* import "BVI" clz = */ 
  /* module mk_v1_clz(Ifc_test#(52)); */
  /*   parameter inWidth = 52; */
  /*   parameter countWidth = 6; */

  /*   default_clock no_clock; */
  /*   default_reset no_reset; */

  /*   method count clz(in); */
  /*   path(in,count); */
  /* endmodule */

  /* (*synthesize*) */
  /* module mk_clz_v1(Ifc_test#(52)); */
  /*   let ifc(); */
  /*   mk_v1_clz _temp(ifc()); */
  /*   return ifc; */
  /* endmodule */

  /* import "BVI" clzi = */ 
  /* module mk_alt_clz(Ifc_test#(52)); */
  /*   parameter W_IN = 52; */
  /*   parameter W_OUT = 6; */

  /*   default_clock no_clock; */
  /*   default_reset no_reset; */

  /*   method out clz(in); */
  /* endmodule */

  /* (*synthesize*) */
  /* module mk_clz_alt(Ifc_test#(52)); */
  /*   let ifc(); */
  /*   mk_alt_clz _temp(ifc()); */
  /*   return ifc; */
  /* endmodule */

endpackage
