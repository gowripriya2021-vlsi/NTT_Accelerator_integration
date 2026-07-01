// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd.
// see LICENSE.incore for more details on licensing terms
/*
Author: Babu P S , babu.ps@incoresemi.com
Created on: Monday 17 August 2020 6:22:16 PM IST

*/

package pwm;

  import Clocks        :: *;
  import Semi_FIFOF    :: *;
  import BUtils        :: *;
  import Vector        :: *;
  import ConfigReg     :: *;
  // import axi4       :: *;
  import axi4l         :: *;
  import apb           :: *;
  import DCBus         :: *;
  import clock_divider :: *;
  import Reserved      :: *;

  `include "pwm.defines"

  export PWMIO              (..);
  export Ifc_pwm            (..);
  export Ifc_pwm_apb        (..);
  export Ifc_pwm_axi4l      (..);
  // export Ifc_pwm_axi4    (..); // ??
  export mk_pwm_block;
  export mkpwm_apb;
  export mkpwm_axi4l;
  // export mkpwm_axi4;

  typedef enum {Byte=0, HWord=1, Word=2, DWord=3} AccessSize deriving(Bits,Eq,FShow);

  typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw), Ifc_pwm#(pwmwidth, channels, outbar_en))
  Ifc_pwm_axi4l#(type aw, type dw, type uw, numeric type pwmwidth, numeric type channels, numeric type outbar_en);

  typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Ifc_pwm#(pwmwidth, channels, outbar_en))
  Ifc_pwm_apb#(type aw, type dw, type uw, numeric type pwmwidth, numeric type channels, numeric type outbar_en);

  typedef struct{
    ReservedZero#(3)     zeros;                 // bit 15:13
    Bit#(1)     cr_pwm_load_values;             // bit 12
    Bit#(1)     cr_rise_interrupt;              // bit 11 Read only
    Bit#(1)     cr_fall_interrupt;              // bit 10 Read only
    Bit#(1)     cr_halfperiod_interrupt;        // bit 9  Read only
    Bit#(1)     cr_rise_interrupt_enable;       // bit 8
    Bit#(1)     cr_fall_interrupt_enable;       // bit 7
    Bit#(1)     cr_halfperiod_interrupt_enable; // bit 6
    Bit#(1)     cr_comp_out_enable;             // bit 5
    Bit#(1)     cr_counter_reset;               // bit 4
    Bit#(1)     cr_output_polarity;             // bit 3
    Bit#(1)     cr_output_enable;               // bit 2
    Bit#(1)     cr_pwm_start;                   // bit 1
    Bit#(1)     cr_pwm_enable;                  // bit 0
  } PwmControl deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(15)     clk_prescalar;                 // bits 15:1
    Bit#(1)      clk_select;                    // bits 0
  } PwmClock deriving(Bits, Eq, FShow);

  interface PWMIO#(numeric type channels, numeric type outbar_en);
    method Vector#(channels,Bit#(1)) pwm_o;
    method Vector#(TMul#(channels, outbar_en),Bit#(1)) pwm_comp;
  endinterface

  interface Ifc_pwm#(numeric type pwmwidth,numeric type channels, numeric type outbar_en);
    (*always_ready, always_enabled*)
    interface PWMIO#(channels, outbar_en) io;
    method Bit#(channels) sb_interrupt;
  endinterface

  function Bit#(n) vec2bits (Vector#(n, Bit#(1)) a);
    let v_n = valueOf(n);
    Bit#(n) _t;
    for (Integer i = 0; i < v_n; i = i + 1) begin
    _t[i] = a[i];
    end
    return _t;
  endfunction:vec2bits

  /*doc:module: PWM implementation Module with DCBus Interface  */
  module [ModWithDCBus#(aw,dw)] mkpwm#(Clock ext_clock, Reset ext_reset)
  (Ifc_pwm#(pwmwidth,channels,outbar_en))
    provisos(
      Add#(1 , _a, TLog#(TDiv#(dw, 8)))
    , Add#(dw, _b, 64)
    , Add#(TExp#(TLog#(dw)), 0, dw)
    , Add#(pwmwidth, _c, dw)
    , Add#(_d,16,pwmwidth)
    , Add#(pwmwidth, _e, 64)
    , Add#(TExp#(TLog#(pwmwidth)), 0, pwmwidth)

    , Add#(a__, TDiv#(dw, 8), 8)
    , Add#(b__, 1, aw)
    , Add#(c__, 2, aw)
    , Mul#(TDiv#(dw, 8), 8, dw)
    , Mul#(TDiv#(pwmwidth, 8), 8, pwmwidth)
    , Add#(d__, TAdd#(TLog#(TAdd#(channels, 1)), 4), aw)
    , Add#(e__,1,channels)
    , Add#(outbar_en,f__,1)
    , Bits#(Bit#(outbar_en), outbar_en)
  );
    let bus_clock <- exposeCurrentClock;
    let bus_reset <- exposeCurrentReset;

    /*doc:func: Unified Function to create vector of DCBus Registers */
    function DCRAddr#(aw,2) attr_gen ( Bit#(2) reg_sel, Integer indx );
      case(reg_sel)
        0: return DCRAddr{addr: ((fromInteger(indx) << 4) + `Pwm_control),
                  min:Sz2, max:Sz4, mask:2'b00};
        1: return DCRAddr{addr: ((fromInteger(indx) << 4) + `Pwm_period),
                  min:Sz1, max:Sz4, mask:2'b00};
        2: return DCRAddr{addr: ((fromInteger(indx) << 4) + `Pwm_duty_cycle),
                  min:Sz1, max:Sz4, mask:2'b00};
        3: return DCRAddr{addr: ((fromInteger(indx) << 4) + `Pwm_deadband_delay),
                  min:Sz1, max:Sz4, mask:2'b00};
      endcase
    endfunction

    /*doc:note: CLK is common for all channels */
    DCRAddr#(aw,2) attr_clk_option  = DCRAddr{addr:`Pwm_clock, min:Sz2, max:Sz4, mask:2'b00};
    /*doc:note: Other attributes are unique to each channel */
    Vector#(channels, DCRAddr#(aw,2)) attr_control        = genWith( attr_gen(unpack(0)) );
    Vector#(channels, DCRAddr#(aw,2)) attr_period_inp     = genWith( attr_gen(unpack(1)) );
    Vector#(channels, DCRAddr#(aw,2)) attr_duty_cyc       = genWith( attr_gen(unpack(2)) );
    Vector#(channels, DCRAddr#(aw,2)) attr_deadband_delay = genWith( attr_gen(unpack(3)) );

    Vector#(channels,Reg#(Bit#(pwmwidth))) period_in;
    Vector#(channels,Reg#(Bit#(pwmwidth))) duty_cycle_in;
    Vector#(channels,Reg#(Bit#(16))) deadbanddelay_in;
    Vector#(channels,Reg#(PwmControl)) control_status;
    for(Integer i=0; i<valueOf(channels); i=i+1) begin
      period_in[i]        <- mkDCBRegRW(attr_period_inp[i],unpack(0));
      duty_cycle_in[i]    <- mkDCBRegRW(attr_duty_cyc[i],unpack(0));
      deadbanddelay_in[i] <- mkDCBRegRW(attr_deadband_delay[i],unpack(0));
      control_status[i]   <- mkDCBRegRW(attr_control[i],unpack(0));
    end

    /*doc:reg: This Register holds the clock source and prescalar values */
    Reg#(PwmClock) rg_clk_control <- mkDCBRegRW(attr_clk_option ,unpack(0));

    MuxClkIfc clock_selection <-mkUngatedClockMux(ext_clock, bus_clock);
    Reset async_reset <- mkAsyncResetFromCR(0,clock_selection.clock_out);

    rule select_clock;
      clock_selection.select(rg_clk_control.clk_select==1);
    endrule

    Reg#(Bit#(15)) sync_clock_divisor <- mkSyncRegFromCC(0, clock_selection.clock_out);
    rule transfer_data_from_clock_domains;
      sync_clock_divisor <= rg_clk_control.clk_prescalar;
    endrule

    Ifc_clock_divider#(15) clk_divider <- mkclock_divider(clocked_by clock_selection.clock_out,
    reset_by async_reset);
    let downclock = clk_divider.slowclock;
    Reset downreset <- mkAsyncReset(0,bus_reset,downclock);

    rule generate_slow_clock;
      clk_divider.set.divisor(sync_clock_divisor);
    endrule

    /*doc:note: PWM variables written in downclock and read at busclock  */
    Vector#(channels,SyncBitIfc#(Bit#(1))) pwm_output         <- replicateM(mkSyncBitToCC(downclock, downreset));
    Vector#(TMul#(channels, outbar_en),SyncBitIfc#(Bit#(1)))
                                           pwm_comp_output    <- replicateM(mkSyncBitToCC(downclock, downreset));
    Vector#(channels,SyncBitIfc#(Bit#(1))) interrupt          <- replicateM(mkSyncBitToCC(downclock, downreset));
    Vector#(channels,SyncBitIfc#(Bit#(1))) pwm_rise_interrupt <- replicateM(mkSyncBitToCC(downclock, downreset));
    Vector#(channels,SyncBitIfc#(Bit#(1))) pwm_fall_interrupt <- replicateM(mkSyncBitToCC(downclock, downreset));
    Vector#(channels,SyncBitIfc#(Bit#(1))) pwm_hfp_interrupt  <- replicateM(mkSyncBitToCC(downclock, downreset));
    Vector#(channels,SyncPulseIfc) pwm_load_val             <- replicateM(mkSyncPulseToCC(downclock, downreset));

    /*doc:reg: Registers operated at Down clock */
    Vector#(channels,Reg#(Bit#(pwmwidth))) counter <- replicateM(mkRegA(0, clocked_by downclock, reset_by downreset));

    /*doc:reg: Registers written at bus clock and read at downclock*/
    Vector#(channels,Reg#(Bit#(pwmwidth))) duty_cycle <- replicateM(mkSyncRegFromCC(0, downclock));
    Vector#(channels,Reg#(Bit#(pwmwidth))) period     <- replicateM(mkSyncRegFromCC(0, downclock));
    Vector#(channels,Reg#(Bit#(16))) deadbanddelay    <- replicateM(mkSyncRegFromCC(0, downclock));

    /*doc:reg:  PWM Variables written at bus clock and read at down clock */
    Vector#(channels,SyncBitIfc#(Bit#(1))) sync_pwm_enable    <- replicateM(mkSyncBitFromCC(downclock));
    Vector#(channels,SyncBitIfc#(Bit#(1))) sync_pwm_start     <- replicateM(mkSyncBitFromCC(downclock));
    Vector#(channels,SyncBitIfc#(Bit#(1))) sync_counter_reset <- replicateM(mkSyncBitFromCC(downclock));
    Vector#(channels,SyncBitIfc#(Bit#(1))) sync_rise_ien      <- replicateM(mkSyncBitFromCC(downclock));
    Vector#(channels,SyncBitIfc#(Bit#(1))) sync_fall_ien      <- replicateM(mkSyncBitFromCC(downclock));
    Vector#(channels,SyncBitIfc#(Bit#(1))) sync_hfp_ien       <- replicateM(mkSyncBitFromCC(downclock));

    for(Integer i=0; i<valueOf(channels); i=i+1) begin
      (*descending_urgency = "reload_input_values_at_rising_edge, rl_update_interrupts" *)

      /*doc:rule: Update Period, Duty Cycle & DBD values
        1. If the pwm_start == 0 then load immediately.
        2. else load when counter rolls back to 0 and stop pwm
      */
      rule reload_input_values_at_rising_edge(((control_status[i].cr_pwm_start == 0) ||
        (pwm_load_val[i].pulse && control_status[i].cr_pwm_start == 1))   &&
        control_status[i].cr_pwm_load_values == 1);
        deadbanddelay[i] <= deadbanddelay_in[i];
        duty_cycle[i]    <= duty_cycle_in[i];
        period[i]        <= period_in[i];
        let temp = control_status[i];
        temp.cr_pwm_load_values = 0;
        temp.cr_pwm_start = 0;
        control_status[i] <= temp;
      endrule

      (* fire_when_enabled, no_implicit_conditions *)
      /*doc:rule: Update values from bus clock to down clock */
      rule rl_update_pwm_variables;
        sync_pwm_enable[i].send(control_status[i].cr_pwm_enable);
        sync_pwm_start[i].send(control_status[i].cr_pwm_start);
        sync_counter_reset[i].send(control_status[i].cr_counter_reset);
        sync_rise_ien[i].send(control_status[i].cr_rise_interrupt_enable);
        sync_fall_ien[i].send(control_status[i].cr_fall_interrupt_enable);
        sync_hfp_ien[i].send(control_status[i].cr_halfperiod_interrupt_enable);
      endrule

      /*doc:rule: Update interrupt values from down clock to bus clock */
      rule rl_update_interrupts;
        let _interrpt_upd = control_status[i];
        _interrpt_upd.cr_rise_interrupt = pwm_rise_interrupt[i].read;
        _interrpt_upd.cr_fall_interrupt = pwm_fall_interrupt[i].read;
        _interrpt_upd.cr_halfperiod_interrupt  = pwm_hfp_interrupt[i].read;
        control_status[i] <= _interrpt_upd;
      endrule

      /*doc:rule: PWM operation at downclock */
      rule compare_and_generate_pwm(sync_pwm_enable[i].read==1 );
        Bit#(pwmwidth) temp_cntr;
        if((counter[i] >= period[i]-1) || (sync_counter_reset[i].read == 1) || (sync_pwm_start[i].read== 0))
          temp_cntr = 0;
        else begin
          temp_cntr = counter[i] + 1;
        end
        counter[i] <= temp_cntr;

        if(temp_cntr == 0) // || temp_cntr == duty_cycle[i] - 2)
          pwm_load_val[i].send;

        if(temp_cntr < zeroExtend(deadbanddelay[i]))
          begin
            pwm_output[i].send(0);
            if(valueOf(outbar_en)==1) pwm_comp_output[i].send(0);
          end
        else if(temp_cntr < duty_cycle[i])
          begin
            pwm_output[i].send(1);
            if(valueOf(outbar_en)==1) pwm_comp_output[i].send(0);
          end
        else if(temp_cntr < duty_cycle[i]+zeroExtend(deadbanddelay[i]))
          begin
            pwm_output[i].send(0);
            if(valueOf(outbar_en)==1) pwm_comp_output[i].send(0);
          end
        else
          begin
            pwm_output[i].send(0);
            if(valueOf(outbar_en)==1) pwm_comp_output[i].send(1);
          end

        let half_period = period[i] >> 1;
        Bit#(1) temp_rise = 0; Bit#(1) int_rise = 0;
        Bit#(1) temp_fall = 0; Bit#(1) int_fall = 0;
        Bit#(1) temp_hfpd = 0; Bit#(1) int_hfpd = 0;
        if((sync_counter_reset[i].read == 0) && (sync_pwm_start[i].read == 1) && (temp_cntr < period[i]-1 ))
        begin
          if(temp_cntr == zeroExtend(deadbanddelay[i])) int_rise  = 1;
          if(temp_cntr >= zeroExtend(deadbanddelay[i])) temp_rise = 1;
          if(temp_cntr == duty_cycle[i])                int_fall  = 1;
          if(temp_cntr >= duty_cycle[i])                temp_fall = 1;
          if(temp_cntr == half_period)                  int_hfpd  = 1;
          if(temp_cntr >= half_period)                  temp_hfpd = 1;
        end
        pwm_rise_interrupt[i].send(temp_rise);
        pwm_fall_interrupt[i].send(temp_fall);
        pwm_hfp_interrupt[i].send(temp_hfpd);
        interrupt[i].send(((int_rise & sync_rise_ien[i].read) |
                           (int_fall & sync_fall_ien[i].read) |
                           (int_hfpd & sync_hfp_ien[i].read)));
      endrule
    end

    interface io= interface PWMIO
      method pwm_o;
        Vector#(channels,Bit#(1)) temp_o;
        for(Integer i=0; i<valueOf(channels); i=i+1) begin
          temp_o[i]=control_status[i].cr_output_enable   ==0 ? 0 :
                    control_status[i].cr_output_polarity ==1 ?
                    pwm_output[i].read : ~pwm_output[i].read;
        end
        return temp_o;
      endmethod
      method pwm_comp;
        Vector#(TMul#(channels, outbar_en),Bit#(1)) temp_comp = replicate(0);
          for(Integer i=0; i<valueOf(TMul#(channels, outbar_en)); i=i+1) begin
            temp_comp[i]=control_status[i].cr_comp_out_enable==0 ? 0 :
                         control_status[i].cr_output_polarity==1 ?
                         pwm_comp_output[i].read : ~pwm_comp_output[i].read;
          end
        return temp_comp;
       endmethod
    endinterface;

    method Bit#(channels) sb_interrupt;
      Vector#(channels,Bit#(1)) temp;
      for(Integer i=0; i<valueOf(channels); i=i+1) begin
          temp[i]=interrupt[i].read;
      end
      return vec2bits(temp);
    endmethod
  endmodule:mkpwm

  module [Module] mk_pwm_block#(Clock pwm_clk, Reset pwm_rst)
  (IWithDCBus#(DCBus#(aw,dw), Ifc_pwm#(pwmwidth,channels,outbar_en)))
  provisos(
      Add#(1 , _a, TLog#(TDiv#(dw, 8)))
    , Add#(dw, _b, 64)
    , Add#(TExp#(TLog#(dw)), 0, dw)
    , Add#(pwmwidth, _c, dw)
    , Add#(_d,16,pwmwidth)
    , Add#(pwmwidth, _e, 64)
    , Add#(TExp#(TLog#(pwmwidth)), 0, pwmwidth)

    , Add#(a__, TDiv#(dw, 8), 8)
    , Add#(b__, 1, aw)
    , Add#(c__, 2, aw)
    , Mul#(TDiv#(dw, 8), 8, dw)
    , Mul#(TDiv#(pwmwidth, 8), 8, pwmwidth)
    , Add#(d__, TAdd#(TLog#(TAdd#(channels, 1)), 4), aw)
    , Add#(e__,1,channels)
    , Add#(f__,outbar_en,1)
    , Bits#(Bit#(outbar_en), outbar_en)
  );
    let ifc <- exposeDCBusIFC(mkpwm(pwm_clk, pwm_rst));
    return ifc;
  endmodule:mk_pwm_block

  module [Module] mkpwm_axi4l#(parameter Integer base, Clock pwm_clk, Reset pwm_rst,
                             Clock dc_clk, Reset dc_rst )
    (Ifc_pwm_axi4l#(aw, dw, uw, pwmwidth, channels, outbar_en))
    provisos(
      Add#(1 , _a, TLog#(TDiv#(dw, 8)))
    , Add#(dw, _b, 64)
    , Add#(TExp#(TLog#(dw)), 0, dw)
    , Add#(pwmwidth, _c, dw)
    , Add#(_d,16,pwmwidth)
    , Add#(pwmwidth, _e, 64)
    , Add#(TExp#(TLog#(pwmwidth)), 0, pwmwidth)

    , Add#(a__, TDiv#(dw, 8), 8)
    , Add#(b__, 1, aw)
    , Add#(c__, 2, aw)
    , Mul#(TDiv#(dw, 8), 8, dw)
    , Mul#(TDiv#(pwmwidth, 8), 8, pwmwidth)
    , Add#(d__, TAdd#(TLog#(TAdd#(channels, 1)), 4), aw)
    , Add#(e__,1,channels)
    , Add#(f__,outbar_en, 1)
    , Bits#(Bit#(outbar_en), outbar_en)
    );

    let device = mk_pwm_block(pwm_clk, pwm_rst);
    Ifc_pwm_axi4l#(aw, dw, uw, pwmwidth, channels, outbar_en) pwm <-
          dc2axi4l(device, base, dc_clk, dc_rst);
    return pwm;
  endmodule:mkpwm_axi4l


  module [Module] mkpwm_apb#( parameter Integer base, Clock pwm_clk, Reset pwm_rst,
                            Clock dc_clk, Reset dc_rst)
    (Ifc_pwm_apb#(aw, dw, uw, pwmwidth, channels, outbar_en))
    provisos(
      Add#(1 , _a, TLog#(TDiv#(dw, 8)))
    , Add#(dw, _b, 64)
    , Add#(TExp#(TLog#(dw)), 0, dw)
    , Add#(pwmwidth, _c, dw)
    , Add#(_d,16,pwmwidth)
    , Add#(pwmwidth, _e, 64)
    , Add#(TExp#(TLog#(pwmwidth)), 0, pwmwidth)

    , Add#(a__, TDiv#(dw, 8), 8)
    , Add#(b__, 1, aw)
    , Add#(c__, 2, aw)
    , Mul#(TDiv#(dw, 8), 8, dw)
    , Mul#(TDiv#(pwmwidth, 8), 8, pwmwidth)
    , Add#(d__, TAdd#(TLog#(TAdd#(channels, 1)), 4), aw)
    , Add#(e__,1,channels)
    , Add#(f__,outbar_en,1)
    , Bits#(Bit#(outbar_en), outbar_en)
    );

    let device = mk_pwm_block(pwm_clk, pwm_rst);
    Ifc_pwm_apb#(aw, dw, uw, pwmwidth, channels, outbar_en) pwm <-
          dc2apb(device, base, dc_clk, dc_rst);
    return pwm;
  endmodule:mkpwm_apb

endpackage
