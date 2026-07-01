/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved.
  See LICENSE.incore for more details.
  Created On:  Mon Feb 28, 2022 11:43:46 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks
  - Babu P S <babu.ps@incoresemi.com> @eflaner
*/
package Retiming;

`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import ConfigReg           :: * ;
  import FIFOF               :: * ;
  import UniqueWrappers      :: * ;
  import Vector              :: * ;
  import RevertingVirtualReg :: * ;
  import PAClib              :: * ;
  import Connectable         :: * ;

  interface Ifc_retimed#(type a, type b);
    method Bool mv_output_valid;
    method Bool mv_ready;
    method Action ma_inputs (a x);
    method ActionValue#(b) mav_output;
    method Action clear;
  endinterface

  interface Ifc_retime#(type a, type b);
    method Action ma_request(a x);
    method ActionValue#(b) mav_response;
  endinterface

  instance Connectable#(Ifc_retimed#(a,b),Ifc_retimed#(b,c));
    module mkConnection#(Ifc_retimed#(a,b) ifc1, Ifc_retimed#(b,c) ifc2)(Empty);
      (*fire_when_enabled*)
      rule rl_drive_inputs(ifc1.mv_output_valid && ifc2.mv_ready);
        let temp <- ifc1.mav_output();
        ifc2.ma_inputs(temp);
      endrule
    endmodule: mkConnection
  endinstance: Connectable

  module [Module] mkretimed_pipe(Ifc_retime#(a,b) in_ifc,
                              Integer in_stages,
                              Integer out_stages,
                              PipeOut#(a) pin,
                              PipeOut#(b) pipe_out)
   provisos (Bits#(a,sa), Bits#(b,sb));

    Reg#(a) rg_in[in_stages];
    for (Integer i = 0; i<in_stages; i = i + 1) begin
      rg_in[i] <- mkRegA(unpack(0));
    end
    /*doc:wire: */
    Wire#(a) wr_in <- mkWire();
    FIFOF#(Bool) rg_valid_in[in_stages];
    for (Integer i = 0; i<in_stages; i = i + 1) begin
      rg_valid_in[i] <- mkUGLFIFOF;
    end

    FIFOF#(Bool) rg_valid_out[out_stages];
    for (Integer i = 0; i<out_stages; i = i + 1) begin
      rg_valid_out[i] <- mkUGLFIFOF;
    end
    Reg#(b) rg_output[out_stages];
    for (Integer i = 0; i<out_stages; i = i + 1) begin
      rg_output[i] <- mkRegA(unpack(0));
    end

    Reg#(Bool) vreg <- mkRevertingVirtualReg(True);

    /*doc:wire: */
    Wire#(b) wr_output <- mkDWire(?);
    /*doc:wire: */
    Wire#(Bool) wr_valid <- mkDWire(False);

    Bool lv_ready = (in_stages > 0)?rg_valid_in[0].notFull():
                         (out_stages> 0)?rg_valid_out[0].notFull: True;


    /*doc:rule: */
    for (Integer i = in_stages -1 ; i > 0; i = i - 1) begin
      rule rl_move_inputs(rg_valid_in[i].notFull && rg_valid_in[i-1].notEmpty);
        rg_in[i] <= rg_in[i - 1];
        rg_valid_in[i].enq(rg_valid_in[i-1].first);
        rg_valid_in[i-1].deq;
      endrule:rl_move_inputs
    end

    /*doc:rule: */
    if (in_stages > 0 && out_stages > 0 ) begin
      rule rl_perform_in(vreg);
        in_ifc.ma_request(rg_in[in_stages-1]);
      endrule:rl_perform_in
      rule rl_perform_out(rg_valid_in[in_stages - 1].notEmpty && rg_valid_out[0].notFull);
        rg_valid_out[0].enq(rg_valid_in[in_stages - 1].first);
        vreg <= False;
        let out <- in_ifc.mav_response();
        rg_output[0] <= out;
        rg_valid_in[in_stages - 1].deq;
      endrule:rl_perform_out

    end
    else if (out_stages > 0) begin
      rule rl_perform_in(vreg);
        in_ifc.ma_request(wr_in);
      endrule: rl_perform_in
      rule rl_perform_out;
        vreg <= False;
        let out <- in_ifc.mav_response();
        rg_output[0] <= out;
      endrule: rl_perform_out
    end
    else if (in_stages > 0) begin
      rule rl_perform_in(vreg);
        in_ifc.ma_request(rg_in[in_stages-1]);
      endrule:rl_perform_in
      rule rl_perform_out(rg_valid_in[in_stages - 1].notEmpty);
        vreg <= False;
        let out <- in_ifc.mav_response();
        wr_output <= out;
        wr_valid <= True;
        rg_valid_in[in_stages - 1].deq;
      endrule:rl_perform_out

    end
    else begin
      rule rl_perform_in(vreg);
        in_ifc.ma_request(wr_in);
      endrule: rl_perform_in
      rule rl_perform_out;
        vreg <= False;
        let out <- in_ifc.mav_response();
        wr_output <= out;
        wr_valid <= True;
      endrule: rl_perform_out
    end
    for (Integer i = out_stages - 1; i>0; i = i - 1) begin
      /*doc:rule: */
      rule rl_move_outputs(rg_valid_out[i].notFull && rg_valid_out[i-1].notEmpty);
        rg_output[i] <= rg_output[i-1];
        rg_valid_out[i].enq(rg_valid_out[i-1].first);
        rg_valid_out[i-1].deq;
      endrule:rl_move_outputs
    end

    rule rl_take_inputs(pin.notEmpty() && lv_ready);
      let x = pin.first();
      if(in_stages > 0) begin
        rg_in[0] <= x;
      end
      else begin
        wr_in <= x;
      end
      if(in_stages > 0)
        rg_valid_in[0].enq(True);
      else if (out_stages > 0)
        rg_valid_out[0].enq(True);
      pin.deq();
    endrule

      method notEmpty = (out_stages > 0)?rg_valid_out[out_stages - 1].notEmpty : wr_valid;
      method first = (out_stages> 0)?rg_output[out_stages - 1]: wr_output;
      method Action deq;
        noAction;
      endmethod
  endmodule : mkretimed_pipe

  module [Module] mkretimed_1(Ifc_retimed#(a, b) in_ifc,
                              Integer in_stages,
                              Integer out_stages,
                              Ifc_retimed#(a, b) ifc)
   provisos (Bits#(a,sa), Bits#(b,sb));

    Reg#(a) rg_in[in_stages];
    for (Integer i = 0; i<in_stages; i = i + 1) begin
      rg_in[i] <- mkRegA(unpack(0));
    end
    /*doc:wire: */
    Wire#(a) wr_in <- mkWire();
    FIFOF#(Bool) rg_valid_in[in_stages];
    for (Integer i = 0; i<in_stages; i = i + 1) begin
      rg_valid_in[i] <- mkUGLFIFOF;
    end

    FIFOF#(Bool) rg_valid_out[out_stages];
    for (Integer i = 0; i<out_stages; i = i + 1) begin
      rg_valid_out[i] <- mkUGLFIFOF;
    end
    Reg#(b) rg_output[out_stages];
    for (Integer i = 0; i<out_stages; i = i + 1) begin
      rg_output[i] <- mkRegA(unpack(0));
    end
    /*doc:wire: */
    Wire#(b) wr_output <- mkDWire(?);
    /*doc:wire: */
    Wire#(Bool) wr_valid <- mkDWire(False);

    Reg#(Bool) vreg <- mkRevertingVirtualReg(True);

    /*doc:rule: */
    for (Integer i = in_stages -1 ; i > 0; i = i - 1) begin
      rule rl_move_inputs(rg_valid_in[i].notFull && rg_valid_in[i-1].notEmpty);
        rg_in[i] <= rg_in[i - 1];
        rg_valid_in[i].enq(rg_valid_in[i-1].first);
        rg_valid_in[i-1].deq;
      endrule:rl_move_inputs
    end

    /*doc:rule: */
    if (in_stages > 0 && out_stages > 0 ) begin
      rule rl_perform_in(rg_valid_in[in_stages - 1].notEmpty && rg_valid_out[0].notFull
                                      && in_ifc.mv_ready());
        in_ifc.ma_inputs(rg_in[in_stages-1]);
      endrule:rl_perform_in
      rule rl_perform_out(in_ifc.mv_output_valid());
        rg_valid_out[0].enq(rg_valid_in[in_stages - 1].first);
        vreg <= False;
        let out <- in_ifc.mav_output();
        rg_output[0] <= out;
        rg_valid_in[in_stages - 1].deq;
      endrule:rl_perform_out

    end
    else if (out_stages > 0) begin
      rule rl_perform_in(in_ifc.mv_ready());
        in_ifc.ma_inputs(wr_in);
      endrule: rl_perform_in
      rule rl_perform_out(in_ifc.mv_output_valid());
        vreg <= False;
        let out <- in_ifc.mav_output();
        rg_output[0] <= out;
      endrule: rl_perform_out
    end
    else if (in_stages > 0) begin
      rule rl_perform_in(in_ifc.mv_ready() && rg_valid_in[in_stages - 1].notEmpty);
        in_ifc.ma_inputs(rg_in[in_stages-1]);
      endrule:rl_perform_in
      rule rl_perform_out(in_ifc.mv_output_valid);
        vreg <= False;
        let out <- in_ifc.mav_output();
        wr_output <= out;
        wr_valid <= True;
        rg_valid_in[in_stages - 1].deq;
      endrule:rl_perform_out

    end
    else begin
      rule rl_perform_in(in_ifc.mv_ready);
        in_ifc.ma_inputs(wr_in);
      endrule: rl_perform_in
      rule rl_perform_out(in_ifc.mv_output_valid);
        vreg <= False;
        let out <- in_ifc.mav_output();
        wr_output <= out;
        wr_valid <= True;
      endrule: rl_perform_out
    end
    for (Integer i = out_stages - 1; i>0; i = i - 1) begin
      /*doc:rule: */
      rule rl_move_outputs(rg_valid_out[i].notFull && rg_valid_out[i-1].notEmpty);
        rg_output[i] <= rg_output[i-1];
        rg_valid_out[i].enq(rg_valid_out[i-1].first);
        rg_valid_out[i-1].deq;
      endrule:rl_move_outputs
    end

    method Action ma_inputs (a x);
      if(in_stages > 0) begin
        rg_in[0] <= x;
      end
      else begin
        wr_in <= x;
      end
      if(in_stages > 0)
        rg_valid_in[0].enq(True);
      else if (out_stages > 0)
        rg_valid_out[0].enq(True);
    endmethod
    method ActionValue#(b) mav_output;
      if (out_stages > 0 ) rg_valid_out[out_stages - 1].deq;
      return (out_stages> 0)?rg_output[out_stages - 1]: wr_output;
    endmethod

    method Action clear;
      for (Integer i = 0; i<in_stages; i = i + 1) begin
        rg_valid_in[i].clear();
      end
      for (Integer i = 0; i<out_stages; i = i + 1) begin
        rg_valid_out[i].clear();
      end
    endmethod

    method mv_ready = (in_stages > 0)?rg_valid_in[0].notFull():
                         (((out_stages> 0)?rg_valid_out[0].notFull: True) && in_ifc.mv_ready());
    method mv_output_valid = (out_stages > 0)?rg_valid_out[out_stages - 1].notEmpty : wr_valid;
  endmodule: mkretimed_1

  module [Module] mkretimed(Ifc_retime#(a, b) in_ifc,
                            Integer in_stages,
                            Integer out_stages,
                            Ifc_retimed#(a, b) ifc)
   provisos (Bits#(a,sa), Bits#(b,sb));

    Reg#(a) rg_in[in_stages];
    for (Integer i = 0; i<in_stages; i = i + 1) begin
      rg_in[i] <- mkRegA(unpack(0));
    end
    /*doc:wire: */
    RWire#(a) wr_in <- mkRWire();
    FIFOF#(Bool) rg_valid_in[in_stages];
    for (Integer i = 0; i<in_stages; i = i + 1) begin
      rg_valid_in[i] <- mkUGLFIFOF;
    end

    FIFOF#(Bool) rg_valid_out[out_stages];
    for (Integer i = 0; i<out_stages; i = i + 1) begin
      rg_valid_out[i] <- mkUGLFIFOF;
    end
    Reg#(b) rg_output[out_stages];
    for (Integer i = 0; i<out_stages; i = i + 1) begin
      rg_output[i] <- mkRegA(unpack(0));
    end
    /*doc:wire: */
    Wire#(b) wr_output <- mkDWire(?);
    /*doc:wire: */
    Wire#(Bool) wr_valid <- mkDWire(False);

    //Reg#(Bool) vreg <- mkRevertingVirtualReg(True);
    Bool inp_valid =  (in_stages > 0) ? rg_valid_in[0].notFull  :
                      (out_stages > 0) ? rg_valid_out[0].notFull : True;
    Bool outp_valid = (out_stages > 0) ? rg_valid_out[out_stages - 1].notEmpty : wr_valid ;

    Rules rls_in  = emptyRules();
    Rules rls_out = emptyRules();
    Rules rls     = emptyRules();
    /*doc:rule: */
    for (Integer i = in_stages -1 ; i > 0; i = i - 1) begin
      rule rl_move_inputs(rg_valid_in[i].notFull && rg_valid_in[i-1].notEmpty);
        rg_in[i] <= rg_in[i - 1];
        rg_valid_in[i].enq(rg_valid_in[i-1].first);
        rg_valid_in[i-1].deq;
      endrule:rl_move_inputs
    end

    /*doc:rule: */
    if (in_stages > 0 && out_stages > 0 ) begin
      rls_in = (rules
      rule rl_perform_in(rg_valid_in[in_stages-1].notEmpty && rg_valid_out[0].notFull);
        in_ifc.ma_request(rg_in[in_stages-1]);
      endrule:rl_perform_in
      endrules);
      rls_out = (rules
      rule rl_perform_out(rg_valid_in[in_stages - 1].notEmpty && rg_valid_out[0].notFull);
        rg_valid_out[0].enq(rg_valid_in[in_stages - 1].first);
        //vreg <= False;
        let out <- in_ifc.mav_response();
        rg_output[0] <= out;
        rg_valid_in[in_stages - 1].deq;
      endrule:rl_perform_out
      endrules);
    end
    else if (out_stages > 0) begin
      rls_in = (rules
      rule rl_perform_in(isValid(wr_in.wget()));
        if( wr_in.wget() matches tagged Valid .a)
          in_ifc.ma_request(a);
        else
          $finish;
      endrule: rl_perform_in
      endrules);
      rls_out = (rules
      rule rl_perform_out(rg_valid_out[0].notFull && isValid(wr_in.wget()));
        //vreg <= False;
        let out <- in_ifc.mav_response();
        rg_valid_out[0].enq(True);
        rg_output[0] <= out;
      endrule: rl_perform_out
      endrules);
    end
    else if (in_stages > 0) begin
      rls_in = (rules
      rule rl_perform_in(rg_valid_in[in_stages - 1].notEmpty);
        in_ifc.ma_request(rg_in[in_stages-1]);
      endrule:rl_perform_in
      endrules);
      rls_out = (rules
      rule rl_perform_out(rg_valid_in[in_stages - 1].notEmpty);
        //vreg <= False;
        let out <- in_ifc.mav_response();
        wr_output <= out;
        wr_valid <= True;
        /* rg_valid_in[in_stages - 1].deq; */
      endrule:rl_perform_out
      endrules);
    end
    else begin
      rls_in = (rules
      rule rl_perform_in(isValid(wr_in.wget()));
        in_ifc.ma_request(fromMaybe(?,wr_in.wget()));
      endrule: rl_perform_in
      endrules);
      rls_out = (rules
      rule rl_perform_out(isValid(wr_in.wget()));
        //vreg <= False;
        let out <- in_ifc.mav_response();
        wr_output <= out;
        wr_valid <= True;
      endrule: rl_perform_out
      endrules);
    end
    rls = rJoinExecutionOrder(rls_in,rls_out);
    addRules(rls);
    for (Integer i = out_stages - 1; i>0; i = i - 1) begin
      /*doc:rule: */
      rule rl_move_outputs(rg_valid_out[i].notFull && rg_valid_out[i-1].notEmpty);
        rg_output[i] <= rg_output[i-1];
        rg_valid_out[i].enq(rg_valid_out[i-1].first);
        rg_valid_out[i-1].deq;
      endrule:rl_move_outputs
    end
	  
    method Action ma_inputs (a x);
      if(in_stages > 0) begin
        rg_in[0] <= x;
      end
      else begin
        wr_in.wset(x);
      end
      if(in_stages > 0)
        rg_valid_in[0].enq(True);
      /* else if (out_stages > 0) */
      /*   rg_valid_out[0].enq(True); */
    endmethod
    method ActionValue#(b) mav_output;
      if (out_stages > 0 ) rg_valid_out[out_stages - 1].deq;
      else if(in_stages > 0) rg_valid_in[in_stages - 1].deq;
      return (out_stages> 0) ? rg_output[out_stages - 1] : wr_output;
    endmethod

    method Action clear;
      for (Integer i = 0; i<in_stages; i = i + 1) begin
        rg_valid_in[i].clear();
      end
      for (Integer i = 0; i<out_stages; i = i + 1) begin
        rg_valid_out[i].clear();
      end
    endmethod

    method mv_ready = inp_valid;
    method mv_output_valid = outp_valid;
  endmodule:mkretimed

endpackage:Retiming
