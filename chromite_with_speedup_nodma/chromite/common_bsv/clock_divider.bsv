////////////////////////////////////////////////////////////////////////////////
//  Filename      : clock_divider.bsv
//  Description   : Implementation of clock Division.
//                  The division will be exactly 'CurrentClock' / 'divisor'.
//
//            1.    If divisor is 0 / 1, the division will not be performed, 
//                  and 'slowclock' interface will switch to default Clock. 
//                  For these divisor values, it should be noted that, except
//                 'clk_bit' method in 'get' sub-interface all other methods
//                  are driven to constants. i.e., *_edge is tied to 0, and 
//                  'clk_pol' will return idle clk polarity. 
//      
//
//            2.    For 50% Duty cycle output, use divisor i.e., multiple of 2
//
//  License       : see LICENSE.incore for more details on licensing terms
/////////////////////////////////////////////////////////////////////////////////
package clock_divider;

`ifdef async_reset
  import RegOverrides  :: *;
`endif
    import Clocks   :: *;

////////////////////////////////////////////////////////////////////////////////
/// Sub Interfaces
////////////////////////////////////////////////////////////////////////////////
    (* always_enabled *)
    /* doc:subifc: interface that converts clock to bit */
    interface Ifc_clk_bit;
        method Bit#(1) out;
    endinterface

    /* doc:subifc: interface that takes parameters to control clock */
    interface Subifc_set_params#(numeric type w);

        /*doc:method: divides the  def_clk with divisor specified through
                          this method. It should be noted that clock module can
                          be disabled by writing '0' */
        method Action divisor(Bit#(w) in);

        /*doc:method: specifies the initial polarity of clk signal in idle duration
                      this finds significance in scenarios like SPI's CPOL */
        method Action clk_pol(Bit#(1) in);
    endinterface

    (* always_enabled *)
     /* doc:subifc: interface that returns info related to clock */
    interface Subifc_get_params;

        /*doc:Ifc: returns bit type value of 'clock_selector' output clock */
        interface Ifc_clk_bit clk_bit;

        /*doc:method: returns the trailing edge of clk signal.
                      if rg_idle_clk ==0, means this denotes a falling edge
                      else, this denotes a rising edge */
        method Bit#(1) tr_edge;

        /*doc:method: returns the leading edge of clk signal.
                      if rg_idle_clk ==0, means this denotes a rising edge
                      else, this denotes a falling edge */
        method Bit#(1) ld_edge;

        /*doc:method: returns True on occurence of an posedge or negedge.
                      This wire is used in counting number of edges elapsed. */
        method Bool    is_edge;

        /*doc:method: shadows the current polarity of rg_clk */
        method Bit#(1) clk_pol;
    endinterface

////////////////////////////////////////////////////////////////////////////////
/// Interface
////////////////////////////////////////////////////////////////////////////////
    interface Ifc_clock_divider#(numeric type width);
        interface Clock slowclock;
        interface Subifc_set_params#(width) set;
        interface Subifc_get_params get;
    endinterface

    import "BVI" ASSIGN1 =
    module mk_pack_clock#(Clock clk)(Ifc_clk_bit);
        default_clock no_clock;
        default_reset no_reset;

        input_clock clk(IN) = clk;
        method OUT out;

        schedule (out) CF (out);
    endmodule

    module mkclock_divider(Ifc_clock_divider#(width));
        let defclock <- exposeCurrentClock;

        Reg#(Bit#(1)) rg_clk      <- mkRegU;
        Reg#(Bit#(1)) rg_idle_clk <- mkRegA(0);
        Reg#(Bit#(1)) rg_ld_edge  <- mkRegA(0);
        Reg#(Bit#(1)) rg_tr_edge  <- mkRegA(0);
        Wire#(Bool)   wr_is_edge  <- mkDWire(False);

        Reg#(Bit#(width)) rg_counter <- mkRegA(0);
        Reg#(Bit#(width)) rg_divisor <- mkRegA(0);
        Bit#(width)  lv_half_divisor =  rg_divisor >> 1;
        Bool clockmux_sel = rg_divisor!=0;

        MakeClockIfc#(Bit#(1)) new_clock <- mkUngatedClock(0);
        MuxClkIfc clock_selector <- mkUngatedClockMux(new_clock.new_clk,defclock);
        Ifc_clk_bit clock_pack <- mk_pack_clock(clock_selector.clock_out);

    ////////////////////////////////////////////////////////////////////////////
    /// Rules
    ////////////////////////////////////////////////////////////////////////////

        (* fire_when_enabled, no_implicit_conditions *)
        rule increment_counter(clockmux_sel);
            if(rg_counter== rg_divisor)begin
                rg_clk        <= ~ rg_clk;
                rg_counter <= 0;
                rg_ld_edge    <= 0;
                rg_tr_edge    <= 1;
                wr_is_edge    <= True;
            end
            else if(rg_counter == lv_half_divisor) begin
                rg_clk        <= ~ rg_clk;
                rg_counter    <= rg_counter + 1;
                rg_ld_edge    <= 1;
                rg_tr_edge    <= 0;
                wr_is_edge    <= True;
            end
            else begin
                rg_counter    <= rg_counter + 1;
                rg_ld_edge    <= 0;
                rg_tr_edge    <= 0;
            end
        endrule

        (* fire_when_enabled, no_implicit_conditions *)
        rule reset_counter(!clockmux_sel);
            rg_clk        <= rg_idle_clk;
            rg_counter    <= 0;
            rg_ld_edge    <= 0;
            rg_tr_edge    <= 0;
        endrule

        (* fire_when_enabled, no_implicit_conditions *)
        rule generate_clock;
            new_clock.setClockValue(rg_clk);
        endrule

        rule select_clock;
            clock_selector.select(clockmux_sel);
        endrule

    ////////////////////////////////////////////////////////////////////////////
    /// Interface Connections / Methods
    ////////////////////////////////////////////////////////////////////////////

        interface slowclock = clock_selector.clock_out;

        interface set = interface Subifc_set_params
            method Action divisor(Bit#(width) in);
                rg_divisor <= (in != 0) ? (in - 1) : 0;
            endmethod

            method Action clk_pol(Bit#(1) in);
                rg_idle_clk <= in;
            endmethod
        endinterface;

        interface get = interface Subifc_get_params

            method tr_edge = rg_tr_edge;
            method ld_edge = rg_ld_edge;
            method is_edge = wr_is_edge;
            method clk_pol = rg_clk;

            interface Ifc_clk_bit clk_bit;
                method out = clock_pack.out;
            endinterface
        endinterface;

    endmodule
endpackage
