// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd.
// See LICENSE.incore for More details
/*--------------------------------------------------------------------------------------------------
Author: Babu P S
  E-mail: info@incoresemi.com
  Description:
     An Atomic SPI peripheral with CLK, COPI and CIPO controls only.
  NCS (Chip Select) can be wrapped in from higher modules.

  Transaction starts by writing to 'put_byte', this will be sent out using COPI
  A simultaneous Rx happens on CIPO that can be read using 'get_byte'. 'put byte' can
  be fired by checking 'is_idle'.

  Although the methods call `put_byte`, `get_byte`, the Data length is parameterizable.
  It can be byte, half-word, word or double word.
  Moreover, the data sent is bit-level precise controlled inside 'put_byte' method.

  An internal timer which divides bus clock with any even value between 2 and 65534 is
  provisioned with this module, when functioning as controller.

--------------------------------------------------------------------------------------------------*/

package spi_atom;

  import DReg           :: *;
  import Clocks         :: *;
  import clock_divider  :: *;

  `include "spi.defines"

  export Tri_state   (..);
  export SPI_IO      (..);
  export SPI_INP     (..);
  export SPI_atomic  (..);
  export mkspi_atom;

  (* always_ready, always_enabled *)
  interface Tri_state#(numeric type m);
    (* prefix="" *)
    method Action in((* port="in" *) Bit#(m) inp);
    (* result="out_en" *)
    method bit out_en;
    (* result="out" *)
    method Bit#(m) out;
  endinterface

  (* always_ready, always_enabled *)
  interface SPI_IO;
    interface Tri_state#(1) copi;
    interface Tri_state#(1) cipo;
    interface Tri_state#(1) sclk;
  endinterface

  interface SPI_INP#(numeric type n);
    method Action  set_mode_lsb(Bit#(2) mode, bit lsbfirst, bit is_ctrllr);
    method Action  spi_prescalar(Bit#(`PSCR_CLK_WIDTH) scalar);
    method Action  spi_en(Bool enable);
    method Action  free_run_clk(Bool clk_en);
    method Action  put_byte(Bit#(n) tx_byte, Bit#(TAdd#(TLog#(n), 1)) bit_cnt);
    method Bool    is_idle;
    method Action  read_remnant;
    method Bool    remnant_complete;
    method ActionValue#(Bit#(n)) get_byte;
  endinterface

  interface SPI_atomic#(numeric type n);
    interface SPI_IO io;
    interface SPI_INP#(n) inp;
    interface Clock spi_clk;
  endinterface

  (* mutually_exclusive = "rl_spi_reset, rl_receive" *)
  (* conflict_free = "rl_transmit, rl_receive" *)
  module mkspi_atom(SPI_atomic#(n)) provisos(
      Add#(8, _a, n)               // Minimum 8 bits
    ,   Add#(TExp#(TLog#(n)), 0, n)  // Should be power of 2
    ,   Mul#(TDiv#(n, 8), 8, n)      // byte wide
    ,   Add#(TLog#(n), 1, m)         // Used for bit counts
    ,   Add#(m, 1, p)                // Used for edge counts
    ,   Log#(TSub#(n,1), q)          // Used for positions
    ,   Add#(1, r, n)                // max possible position
    ,   Add#(_b, q, m)               // postion < bit count
    );

  let bus_clock <- exposeCurrentClock;
  let bus_reset <- exposeCurrentReset;

  /* doc:note: CPOL: Clock Polarity during Idle state (duration)
      leading edge is rising edge when CPOL = 0
      leading edge is falling edge when CPOL =1

               CPHA: Clock Phase
      At CPHA=0
        on trailing edge of clock data changes in the "out"
        on leading edge of clock data captured in the "in"
      At CPHA=1
        on trailing edge of clock data captured in the "in"
        on leading edge of clock data changes in the "out"
  */

  Reg#(bit)     rg_sclk           <- mkReg(?);
  Wire#(bit)    wr_sclk           <- mkBypassWire();
  Wire#(bit)    wr_ld_edge        <- mkDWire(0);
  Wire#(bit)    wr_tr_edge        <- mkDWire(0);
  Reg#(Bit#(p)) rg_spi_clk_edge   <- mkReg(0);
  Reg#(Bit#(`PSCR_CLK_WIDTH)) rg_scalar <- mkReg(0);

  /* doc: reg:  TX Signals */
  Reg#(Bool)    rg_tx_valid       <- mkDReg(False);    // Data Valid Pulse
  Reg#(Bit#(n)) rg_tx_byte        <- mkReg(0);         // Byte to transmit on Output
  Reg#(Bool)    rg_tx_set         <- mkReg(False);     // Transmit Ready for next byte
  Reg#(bit)     rg_spi_send       <- mkRegU;
  Wire#(bit)    wr_copi           <- mkBypassWire();

  /* doc: reg:  RX Signals */
  Reg#(Bit#(n)) rg_rx_byte        <- mkReg(0);         // Byte received on Input line
  Reg#(Bit#(n)) rg_rx_byte_copy   <- mkReg(0);         // Shadow of byte received on Input line
  Reg#(Bool)    rg_rx_valid       <- mkDReg(False);    // Data Valid pulse (1 clock cycle)
  Wire#(bit)    wr_cipo           <- mkBypassWire();

  Reg#(Bit#(q)) rg_bit_pos        <- mkReg(0);
  Reg#(Bit#(m)) rg_rx_bit_cnt     <- mkReg(0);

  /* doc: reg:  SPI State Elements */
  Reg#(Bit#(2)) rg_mode           <- mkReg(0);
  Reg#(Bool)    rg_is_ctrler      <- mkReg(True);
  Reg#(Bool)    rg_lsb            <- mkReg(False);
  Reg#(Bool)    rg_spi_en         <- mkReg(False);
  Reg#(Bool)    rg_clk_en         <- mkReg(False);
  Wire#(Bit#(m)) wr_count         <- mkDWire(0);

  /* doc: reg:  Internal state Elements */
  Wire#(Bool)   wr_xferd          <- mkDWire(False);
  Wire#(bit)    wr_spi_clk        <- mkDWire(0);
  Reg#(Bool)    rg_flush          <- mkDReg(False);

//    TriState#(Bit#(1)) tCOPI  <- mkTriState(rg_is_ctrler, rg_spi_send);
//    TriState#(Bit#(1)) tSCLK  <- mkTriState(rg_is_ctrler, rg_sclk);
//    TriState#(Bit#(1)) tCIPO  <- mkTriState(!rg_is_ctrler, rg_spi_send);

  Ifc_clock_divider#(`PSCR_CLK_WIDTH) clk_divider <- mkclock_divider;

  /* doc: rule : Rule to reset all state elements on peripheral disable */
  (* fire_when_enabled, no_implicit_conditions *)
  rule rl_spi_reset( !rg_spi_en );
    clk_divider.set.clk_pol(rg_mode[1]);
    clk_divider.set.divisor(0);
    rg_spi_clk_edge  <= 0;
    rg_sclk          <= rg_mode[1];

    rg_tx_valid      <= False;
    rg_tx_byte       <= 0;
    rg_tx_set        <= True;
    //rg_spi_send      <= 0; // Shouldn't be Z ?

    rg_rx_byte       <= 0;
    //rg_rx_valid      <= False;
  endrule

  (* fire_when_enabled, no_implicit_conditions *)
  rule rl_assign_clks(rg_spi_en);
    wr_spi_clk       <= clk_divider.get.clk_pol;
    if(!rg_is_ctrler) begin
      Bool is_edge = (rg_sclk != wr_sclk);
      wr_ld_edge     <= pack(is_edge && wr_sclk != rg_mode[1]);
      wr_tr_edge     <= pack(is_edge && wr_sclk == rg_mode[1]);
      rg_sclk        <= wr_sclk ;
    end
  endrule

   (* fire_when_enabled, no_implicit_conditions *)
  rule rl_latch_edges(rg_spi_en);
    if(wr_xferd) begin
      rg_tx_set            <= False;
      rg_spi_clk_edge      <= zeroExtend(wr_count) << 1 ;  // 2 edges per bit
      if(rg_is_ctrler) begin // Handle clock only in controller mode.
        rg_sclk            <= rg_mode[1];
        clk_divider.set.divisor(rg_scalar);
      end
    end
    else if(rg_spi_clk_edge != 0) begin
      rg_tx_set            <= False;
      if(rg_is_ctrler) begin
        rg_sclk            <= wr_spi_clk;
      end
      let edge_cnt = (!rg_is_ctrler && unpack(wr_ld_edge | wr_tr_edge)) ||
               clk_divider.get.is_edge  ;
      if(edge_cnt) begin
        rg_spi_clk_edge  <= rg_spi_clk_edge - 1;
      end
    end
    else begin
      if(rg_is_ctrler) begin
        if(rg_clk_en) begin
          clk_divider.set.divisor(rg_scalar);
        end else begin
          clk_divider.set.divisor(0);
          rg_sclk          <= rg_mode[1];
        end
      end
      rg_tx_set            <= True;
    end
  endrule

   /* doc: rule:  This rule handles sending 'bit_cnt' bits of data through Output line
          line from rg_tx_byte  The data will be transferred only on rg_tx_set to low*/
  (* fire_when_enabled, no_implicit_conditions *)
  rule rl_transmit(rg_spi_en);
    bit ld_edge = 0;
    bit tr_edge = 0;
    if(rg_is_ctrler) begin
      ld_edge = clk_divider.get.ld_edge ;
      tr_edge = clk_divider.get.tr_edge ;
    end
    else begin
      ld_edge = wr_ld_edge;
      tr_edge = wr_tr_edge;
    end
    if (!rg_tx_set && ( (rg_tx_valid && !unpack(rg_mode[0])) ||
       (unpack((ld_edge & rg_mode[0]) | (tr_edge & ~rg_mode[0]))) )) begin
      rg_tx_valid         <= False;
      if(rg_lsb) begin
        rg_spi_send     <= rg_tx_byte[0];
        rg_tx_byte      <= rg_tx_byte >> 1;
      end
      else begin
        rg_spi_send     <= rg_tx_byte[valueOf(r)];
        rg_tx_byte      <= rg_tx_byte << 1;
      end
    end
  endrule

  /* doc: rule:  This rule handles sampling the Input line and arrange the  sampled data into the
  rg_rx_byte which will be transferred once 'bit_cnt' bits are received. The higher modules will
  be able to read the received data by setting the Data_valid pulse */
  (* fire_when_enabled, no_implicit_conditions *)
  rule rl_receive(rg_spi_en);
    bit ld_edge = 0;
    bit tr_edge = 0;
    if(rg_is_ctrler) begin
      ld_edge = clk_divider.get.ld_edge ;
      tr_edge = clk_divider.get.tr_edge ;
    end
    else begin
      ld_edge = wr_ld_edge;
      tr_edge = wr_tr_edge;
    end
    if (rg_tx_set) begin                     // Yet for a transaction
      rg_rx_byte          <= 0;
      if(rg_lsb) begin
        rg_bit_pos      <= 0 ;
        rg_rx_bit_cnt <= (wr_count - 1);
      end
      else begin
        let r_val = fromInteger(valueOf(r));
        rg_bit_pos      <= r_val ;
        rg_rx_bit_cnt <= (r_val - (wr_count - 1));
      end
    end
    else if ( unpack((ld_edge & ~(rg_mode[0])) | (tr_edge & rg_mode[0]))) begin
      let recvd_val = rg_is_ctrler ? wr_cipo : wr_copi ;
      rg_bit_pos <= (rg_lsb) ? (rg_bit_pos + 1) : (rg_bit_pos - 1) ;
      if (rg_rx_bit_cnt == zeroExtend(rg_bit_pos)) begin
        rg_rx_byte_copy <= (zeroExtend(recvd_val) << rg_bit_pos) | rg_rx_byte;
        rg_rx_byte  <= 0;
        rg_rx_valid <= True;                  // Report that data is ready
      end
      else begin
        rg_rx_byte <= (zeroExtend(recvd_val) << rg_bit_pos) | rg_rx_byte;
      end
    end
  endrule

  (* fire_when_enabled, no_implicit_conditions *)
  rule rl_push_remnant(!rg_is_ctrler && rg_flush && !rg_rx_valid);
    rg_rx_byte_copy <= rg_rx_byte ;
    rg_rx_valid <= True;
    rg_flush        <= True ;
  endrule

  /* doc: interface: Exposed to the IO of chip to interact with SPI peripheral */
  interface io = interface SPI_IO
    interface copi = interface Tri_state
      method bit out;
        return rg_spi_send;
      endmethod
      method bit out_en;
        return pack(rg_is_ctrler);
      endmethod
      method Action in(bit dat);
        wr_copi <= dat ;
      endmethod
    endinterface;

    interface sclk = interface Tri_state
      method bit out ;
        return rg_sclk;
      endmethod
      method bit out_en;
        return pack(rg_is_ctrler);
      endmethod
      method Action in(bit clk);
        wr_sclk <= clk;
      endmethod
    endinterface;

    interface cipo = interface Tri_state
      method Action in(bit dat);
        wr_cipo <= dat ;
      endmethod
      method bit out_en;
        return pack(!rg_is_ctrler);
      endmethod
      method bit out ;
        return rg_spi_send;
      endmethod
    endinterface;
  endinterface;



  /* doc:interface: Used by higher modules to control the SPI data transfer module */
  interface inp = interface SPI_INP
    /* doc: method: Prerequisites to set Mode, format and function */
    method Action set_mode_lsb(Bit#(2) mode, bit lsbfirst, bit is_ctrllr) if(!rg_spi_en);
      rg_mode <= mode;
      rg_lsb  <= unpack(lsbfirst);
      rg_is_ctrler <= unpack(is_ctrllr);
    endmethod

    /* doc:method: scalar should be minimum of 2 and should be even value */
    method Action spi_prescalar(Bit#(`PSCR_CLK_WIDTH) scalar) if(!rg_spi_en);
      if(scalar > 1 && scalar < '1 )
         rg_scalar <= ((scalar[0] == 1) ? (scalar + 1) : scalar );
      else
         rg_scalar <= 0;
    endmethod

    /* doc:method: Enable or disable SPI Peripheral */
    method Action spi_en(Bool enable);
      rg_spi_en <= enable;
    endmethod

    /* doc:method: Send 'bit_cnt' specified bits from 'tx_byte' through rg_spi_send */
    method Action put_byte(Bit#(n) tx_byte, Bit#(m) bit_cnt) if(rg_tx_set);
      wr_xferd    <= True;
      wr_count    <= bit_cnt;
      rg_tx_valid <= True;
      rg_tx_byte  <= tx_byte;
    endmethod

    /* doc:method: Allows the spi_clk to run when rg_spi_en = 1 and rg_tx_set = 1
      This is used to drive the components at higher level at spi_clk frequencies */
    method Action free_run_clk(Bool clk_en);
      rg_clk_en <= clk_en;
      clk_divider.set.divisor( clk_en ? rg_scalar : 0 );
    endmethod

    /* doc:method: Indicates the status of Transaction to higher modules */
    method Bool is_idle;
      return rg_tx_set;
    endmethod

    /* doc:method: Allows the Top-level SPI to read the remnant data before disabling
       in peripheral mode. */
    method Action read_remnant; // if(!rg_is_ctrler);
      rg_flush <= True;
    endmethod

    /* doc:method: Indicates the Top-level SPI in peripheral mode to complete
       as remnant data is completely pushed */
    method Bool remnant_complete; // if(!rg_is_ctrler);
      return !rg_flush;
    endmethod

    /* doc:method: returns 'bit_cnt' specified bits stored in rg_rx_byte */
    method ActionValue#(Bit#(n)) get_byte if(rg_rx_valid && rg_spi_en);
      rg_rx_valid   <= False;
      return rg_rx_byte_copy;
    endmethod
  endinterface;

  /* doc:interface: Clock interface that can be used to drive at spi speeds */
  interface spi_clk = clk_divider.slowclock;

endmodule // spi_atom
endpackage
