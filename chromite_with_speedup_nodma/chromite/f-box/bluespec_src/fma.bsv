/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved. See LICENSE.incore for more details.
  Created On:  Mon Mar 07, 2022 09:58:39 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks
*/
package fma;

`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import Retiming     :: * ;
  import mulAddRec    :: * ;
  import recFN        :: * ;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import FIFOF_       :: * ;
  import Connectable  :: * ;

  // Type of module to be instantiated.
  typedef enum{None=0, Pre=1,Mac=2,Post=4,Round=8,Pre_mac=3,Mac_post=6,Post_round=12} ModName 
    deriving (Bits,Eq,FShow);

  // Custom Input and Output types to ease writing code.
  // The modules are chained i.e the output of one module is fed to the input of the another. In a
  // scenario where the output of the producer and the input of the consumer are the same, the
  // type is named after the consumer to ensure convention and avoid redeclarations.
  typedef Tuple8#(Bit#(sigwidth),Bit#(sigwidth),Bit#(TMul#(sigwidth,2)),Bit#(6),
    Bit#(TLog#(TAdd#(sigwidth,1))), Bit#(TAdd#(expwidth,2)), Bit#(TAdd#(sigwidth,2)), Bit#(3)) 
    Mac_in#(numeric type expwidth, numeric type sigwidth);
  typedef Tuple5#(Bit#(2),Recfmt#(expwidth,sigwidth),Recfmt#(expwidth,sigwidth),
    Recfmt#(expwidth,sigwidth),Bit#(3)) 
    Pre_in#(numeric type expwidth, numeric type sigwidth);
  typedef Tuple6#(Bit#(6),Bit#(TLog#(TAdd#(sigwidth,1))), Bit#(TAdd#(expwidth,2)),
    Bit#(TAdd#(sigwidth,2)),Bit#(TAdd#(1,TMul#(sigwidth,2))),Bit#(3)) 
    Post_in#(numeric type expwidth, numeric type sigwidth);  
  typedef Tuple2#(Recfmt#(expwidth,sigwidth),Bit#(5)) 
    Round_out#(numeric type expwidth, numeric type sigwidth);
  typedef Tuple8#(Bit#(1),Bit#(1),Bit#(1),Bit#(1),Bit#(1),Bit#(TAdd#(expwidth,2)),
    Bit#(TAdd#(sigwidth,3)),Bit#(3)) 
    Round_in#(numeric type expwidth, numeric type sigwidth);
    
  // Custom struct to define the module configuration
  typedef struct{
    ModName name;
    Integer in;
    Integer out;
  }ModConfig deriving(Bits, Eq);

  // A generic type to store the ifcs of all instantiated modules. Its useful to write the for loop
  // and handle all instantiations the same way.
  typedef union tagged{
    Ifc_retimed#(Pre_in#(expwidth,sigwidth),   Mac_in#(expwidth,sigwidth)) Pre;
    Ifc_retimed#(Pre_in#(expwidth,sigwidth),   Post_in#(expwidth,sigwidth)) Pre_mac;
    Ifc_retimed#(Post_in#(expwidth,sigwidth),  Round_out#(expwidth,sigwidth)) Post_round;
    Ifc_retimed#(Post_in#(expwidth,sigwidth),  Round_in#(expwidth,sigwidth)) Post;
    Ifc_retimed#(Mac_in#(expwidth,sigwidth),  Round_in#(expwidth,sigwidth)) Mac_post;
    Ifc_retimed#(Round_in#(expwidth,sigwidth), Round_out#(expwidth,sigwidth)) Round;
    Ifc_retimed#(Mac_in#(expwidth,sigwidth),  Post_in#(expwidth,sigwidth)) Mac;
  }ModIfcs#(numeric type expwidth,numeric type sigwidth);

  typedef Ifc_retimed#(Pre_in#(expwidth,sigwidth),Round_out#(expwidth,sigwidth)) 
    Ifc_fma#(numeric type expwidth,numeric type sigwidth);


  /*doc:module: This module instantiates and chains all the verilog modules(retimed) of FMA. The
   * configuration structure consists of 4 nodes of the ModConfig type where each node carries the
   * configuration of the individual modules which are retimed. All the retimed modules are then
   * chained to produce the final output(i.e the effective operation is FMA). In case where multiple
   * modules are chained together (before retiming) i.e. Pre_mac, Post_round etc, lesser number of
   * nodes(<4) are needed to represent the configuration. However, the length of the array should
   * still be 4 and the nodes towards the end of the array should have the name marked as `None` 
   * as opposed to shrinking the length of the config array. Example configurations:
   *   * No chaining before retiming
   *     ```
   *       ModConfig cfg[4] = {
   *         ModConfig{name: Pre,in: 2, out: 2},
   *         ModConfig{name: Mac, in: 0, out: 2},
   *         ModConfig{name: Post, in: 0, out: 2},
   *         ModConfig{name: Round, in: 0, out: 2}}; 
   *     ```
   *   * Chained Pre_mac
   *     ```
   *       ModConfig cfg[4] = {
   *         ModConfig{name: Pre_mac,in: 2, out: 2},
   *         ModConfig{name: Post, in: 0, out: 2},
   *         ModConfig{name: Round, in: 0, out: 2}, 
   *         ModConfig{name: None, in: ?, out: ?}};
   *     ```
   * The fundamental assumption across the module is that the data flow looks like:
   *   Pre -> Mac -> Post -> Round
   * This assumption is exploited while writing the generic instantiations and chaining to reduce
   * the code necessary(handling other types of ifcs).
  */
  module [Module] mkfma#(parameter Vector#(4,ModConfig) iconfig)(Ifc_fma#(expwidth,sigwidth)) provisos(
    Add#(b__, TAdd#(sigwidth, sigwidth), TAdd#(1, TMul#(sigwidth, 2))),
    Add#(a__, sigwidth, TAdd#(1, TMul#(sigwidth, 2)))
  );

    `ifdef norec
    Vector#(3,Ifc_fNToRecFN#(expwidth,sigwidth))  in_cvt  <- replicateM(mk_fNToRecFN());
    Ifc_recFNToFN#(expwidth,sigwidth)             out_cvt <- mk_recFNToFN();
    `endif

  
    Ifc_mulAddRecFNToRaw_preMul#(expwidth,sigwidth) premul <- mk_mulAddRecFNToRaw_preMul();
    Ifc_mulAddRecFNToRaw_postMul#(expwidth,sigwidth) postmul <- mk_mulAddRecFNToRaw_postMul();
    Ifc_roundRawFNToRecFN#(expwidth,sigwidth,0) round <- mk_roundRawFNToRecFN();
    Ifc_MAC#(sigwidth) mac <- mk_MAC();

    // Variable to track the interface of the last valid retimed module in the list;
    Integer last = 3;

    // Variable to store the interfaces of retimed modules
    ModIfcs#(expwidth,sigwidth) ifcs[4];

    // Iterate over all the configuration nodes and instantiate the retimed modules appropriately.
    // The modules are also chained as they are instantitated.
    for (Integer i = 0; i < 4; i=i+1) begin
      case(iconfig[i].name) matches
        Pre: begin
          // Wire to store the values which needed to be returned as a part of the result.
          RWire#(Bit#(3)) _temp <- mkRWire();
          // Convert the ifc of the combo module into the generic Ifc_retime as expected by the
          // retiming module. This is just a 1 to 1 conversion in the bsv world and does not
          // translate to any additional overheads in the generated verilog.
          let in_ifc = interface Ifc_retime
            method Action ma_request(Pre_in#(expwidth,sigwidth) x);
              `ifdef norec
              in_cvt[0].request(truncate(tpl_2(x)));
              in_cvt[1].request(truncate(tpl_3(x)));
              in_cvt[2].request(truncate(tpl_4(x)));
              premul.request(1,tpl_1(x),in_cvt[0].out(),in_cvt[1].out(),in_cvt[2].out(),tpl_5(x));
              `else
              premul.request(1,tpl_1(x),tpl_2(x),tpl_3(x),tpl_4(x),tpl_5(x));
              `endif
              _temp.wset(tpl_5(x));
            endmethod
            // Read all ports and construct the return packet.
            method ActionValue#(Mac_in#(expwidth,sigwidth))
                mav_response;
              return tuple8(
                premul.mulAddA,
                premul.mulAddB,
                premul.mulAddC,
                premul.intermed_compactState,
                premul.intermed_CDom_CAlignDist,
                premul.intermed_sExp,
                premul.intermed_highAlignedSigC,
                fromMaybe(?,_temp.wget()));
            endmethod 
          endinterface;
          let ifc();
          // Instantiate the retimed module
          mkretimed#(in_ifc,iconfig[i].in,iconfig[i].out) _temp(ifc());
          // Store the ifc and tag the type(mainly to avoid redeclarations and compiler errors)
          ifcs[i] = tagged Pre ifc;
        end
        Mac: begin
          RWire#(Post_in#(expwidth,sigwidth)) wr_res <- mkUnsafeRWire();
          let in_ifc = interface Ifc_retime
            method Action ma_request(Mac_in#(expwidth,sigwidth) x);
              let res = tuple6(
                tpl_4(x),
                tpl_5(x),
                tpl_6(x),
                tpl_7(x),
                mac.request(tpl_1(x),tpl_2(x),tpl_3(x)),
                tpl_8(x));
              wr_res.wset(res);
            endmethod
            method ActionValue#(Post_in#(expwidth,sigwidth)) mav_response;
              return fromMaybe(?,wr_res.wget());
            endmethod
          endinterface;
          let ifc();
          mkretimed#(in_ifc,iconfig[i].in,iconfig[i].out) _temp(ifc());
          ifcs[i] = tagged Mac ifc;
          // Make connection with the retimed module of the previous stage.
          mkConnection(ifcs[i-1].Pre,ifc);
        end
        Post: begin
          RWire#(Bit#(3)) _temp <- mkRWire();
          let in_ifc = interface Ifc_retime
            method Action ma_request(Post_in#(expwidth,sigwidth) x);
              postmul.request(tpl_1(x),tpl_3(x),tpl_2(x),tpl_4(x),tpl_5(x),tpl_6(x));
              _temp.wset(tpl_6(x));
            endmethod
            method ActionValue#(Round_in#(expwidth,sigwidth)) mav_response;
              return tuple8(postmul.invalidExc(), postmul.out_isNaN(), postmul.out_isInf(),
                postmul.out_isZero(), postmul.out_sign(), postmul.out_sExp(), postmul.out_sig()
                ,fromMaybe(?,_temp.wget()));
            endmethod
          endinterface;
          let ifc();
          mkretimed#(in_ifc,iconfig[i].in,iconfig[i].out) _temp(ifc());
          ifcs[i] = tagged Post ifc;
          // Exploit assumption to narrow the possible modules which can feed to the Post module i.e
          // only Pre and Pre_mac.
          if(ifcs[i-1] matches tagged Pre_mac .x) 
            mkConnection(x,ifc);
          else
            mkConnection(ifcs[i-1].Mac,ifc);
        end
        Round: begin
          let in_ifc = interface Ifc_retime
            method Action ma_request(Round_in#(expwidth,sigwidth) x);
              round.request(1, tpl_1(x), 1'b0, tpl_2(x),tpl_3(x),
                tpl_4(x), tpl_5(x), tpl_6(x), tpl_7(x), tpl_8(x)); 
            endmethod
            method ActionValue#(Round_out#(expwidth,sigwidth)) mav_response;
              `ifdef norec
              out_cvt.request(round.out());
              return tuple2({0,out_cvt.out()}, round.exceptionFlags());
              `else
              return tuple2(round.out(), round.exceptionFlags());
              `endif
            endmethod
          endinterface;
          let ifc();
          mkretimed#(in_ifc,iconfig[i].in,iconfig[i].out) _temp(ifc());
          ifcs[i] = tagged Round ifc;
          last = i;
          if(ifcs[i-1] matches tagged Mac_post .x)
            mkConnection(x,ifc);
          else
            mkConnection(ifcs[i-1].Post,ifc);
        end
        Pre_mac: begin
          RWire#(Post_in#(expwidth,sigwidth)) wr_res <- mkUnsafeRWire();
          let in_ifc =
            interface Ifc_retime
              method Action ma_request(Pre_in#(expwidth,sigwidth) x);
                `ifdef norec
                in_cvt[0].request(truncate(tpl_2(x)));
                in_cvt[1].request(truncate(tpl_3(x)));
                in_cvt[2].request(truncate(tpl_4(x)));
                premul.request(1,tpl_1(x),in_cvt[0].out(),in_cvt[1].out(),in_cvt[2].out(),tpl_5(x));
                `else
                premul.request(1,tpl_1(x),tpl_2(x),tpl_3(x),tpl_4(x),tpl_5(x));
                `endif
                let res = tuple6(
                  premul.intermed_compactState,
                  premul.intermed_CDom_CAlignDist,
                  premul.intermed_sExp,
                  premul.intermed_highAlignedSigC,
                  mac.request(premul.mulAddA(),premul.mulAddB(),premul.mulAddC()),
                  tpl_5(x));
                wr_res.wset(res);
              endmethod
              method ActionValue#(Post_in#(expwidth,sigwidth)) mav_response;
                return fromMaybe(?,wr_res.wget());
              endmethod
            endinterface;
          let ifc();
          mkretimed#(in_ifc,iconfig[i].in,iconfig[i].out) _temp(ifc());
          ifcs[i] = tagged Pre_mac ifc;
        end
        Mac_post: begin
          RWire#(Bit#(3)) _temp <- mkUnsafeRWire();
          let in_ifc = interface Ifc_retime
            method Action ma_request(Mac_in#(expwidth,sigwidth) x);
              let res = mac.request(tpl_1(x),tpl_2(x),tpl_3(x));
              postmul.request(tpl_4(x),tpl_6(x),tpl_5(x),tpl_7(x),res,tpl_8(x));
              _temp.wset(tpl_8(x));
            endmethod
            method ActionValue#(Round_in#(expwidth,sigwidth)) mav_response;
              return tuple8(postmul.invalidExc(), postmul.out_isNaN(), postmul.out_isInf(),
                postmul.out_isZero(), postmul.out_sign(), postmul.out_sExp(), postmul.out_sig(),
                fromMaybe(?,_temp.wget()));
            endmethod
          endinterface;
          let ifc();
          mkretimed#(in_ifc,iconfig[i].in,iconfig[i].out) _temp(ifc());
          ifcs[i] = tagged Mac_post ifc;       
          mkConnection(ifcs[i-1].Pre,ifc);
        end
        Post_round: begin
          let in_ifc = interface Ifc_retime
            method Action ma_request(Post_in#(expwidth,sigwidth) x);
              postmul.request(tpl_1(x),tpl_3(x),tpl_2(x),tpl_4(x),tpl_5(x),tpl_6(x));
              round.request(1, postmul.invalidExc(), 1'b0, postmul.out_isNaN(), postmul.out_isInf(),
                postmul.out_isZero(), postmul.out_sign(), postmul.out_sExp(), postmul.out_sig(), tpl_6(x)); 
            endmethod
            method ActionValue#(Round_out#(expwidth,sigwidth)) mav_response;
              `ifdef norec
              out_cvt.request(round.out());
              return tuple2({0,out_cvt.out()}, round.exceptionFlags());
              `else
              return tuple2(round.out(), round.exceptionFlags());
              `endif
            endmethod
          endinterface;
          let ifc();
          mkretimed#(in_ifc,iconfig[i].in,iconfig[i].out) _temp(ifc());
          ifcs[i] = tagged Post_round ifc;
          last = i;
          if(ifcs[i-1] matches tagged Pre_mac .x) 
            mkConnection(x,ifc);
          else
            mkConnection(ifcs[i-1].Mac,ifc);
        end
      endcase
    end

    // Construct interface for the external world. Assumptions are exploited here too i.e inputs
    // feed into one of Pre_mac or Pre modules and outputs from the Round or the Post_round
    // modules only. The last variable is used here to extract the correct ifc from the array to
    // ensure functionality.
    method Action ma_inputs(Tuple5#(Bit#(2),Recfmt#(expwidth,sigwidth),Recfmt#(expwidth,sigwidth),
      Recfmt#(expwidth,sigwidth),Bit#(3)) inp);
        if(ifcs[0] matches tagged Pre_mac .x)
          x.ma_inputs(inp);
        else
          ifcs[0].Pre.ma_inputs(inp);
    endmethod
    method Bool mv_ready;
        if(ifcs[0] matches tagged Pre_mac .x)
          return x.mv_ready;
        else
          return ifcs[0].Pre.mv_ready;
    endmethod
    
    method ActionValue#(Tuple2#(Recfmt#(expwidth,sigwidth),Bit#(5))) mav_output;
      ActionValue#(Tuple2#(Recfmt#(expwidth,sigwidth),Bit#(5))) _met;
      if(ifcs[last] matches tagged Post_round .x)
        _met = x.mav_output;
      else 
        _met = ifcs[last].Round.mav_output;
      let temp <- _met;
      return temp;
    endmethod
    method Bool mv_output_valid;
      if(ifcs[last] matches tagged Post_round .x)
        return x.mv_output_valid;
      else
        return ifcs[last].Round.mv_output_valid;
    endmethod
  endmodule


endpackage
