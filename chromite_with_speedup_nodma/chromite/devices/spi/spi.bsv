// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd.
// See LICENSE.incore for More details
/*--------------------------------------------------------------------------------------------------
    Author: Babu P S
    Email id: info@incoresemi.com
--------------------------------------------------------------------------------------------------*/

package spi;

  import spi_atom          :: *;
  import FIFOLevel         :: *;
  import DCBus             :: *;
  import DReg              :: *;
  import Reserved          :: *;
  import Vector            :: *;
  import Clocks            :: *;
  import axi4l             :: *;
  import apb               :: *;

  import spi_params        :: *;

  //`include "spi.defines"
  `include "Logger.bsv"

  export Tri_state          (..);
  export SPI_IO             (..);
  export Ifc_spi            (..);
  export Ifc_spi_apb        (..);
  export Ifc_spi_axi4l      (..);
  export mk_spi_block;
  export mkspi_apb;
  export mkspi_axi4l;

  typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw), Ifc_spi#(periph_count, fifo_depth))
    Ifc_spi_axi4l#(type aw, type dw, type uw, numeric type periph_count, numeric type fifo_depth);
  typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Ifc_spi#(periph_count,  fifo_depth))
    Ifc_spi_apb#(type aw, type dw, type uw, numeric type periph_count, numeric type fifo_depth);

    // SPI Interface with chip select
  (* always_ready, always_enabled *)
  interface SPI_IO#(numeric type periph_count);
    (* prefix = "copi" *)
    interface Tri_state#(1) copi;
    (* prefix = "cipo" *)
    interface Tri_state#(1) cipo;
    (* prefix = "sclk" *)
    interface Tri_state#(1) sclk;
    (* prefix = "ncs" *)
    interface Tri_state#(periph_count) ncs;
  endinterface

  interface Ifc_spi#(numeric type periph_count, numeric type fifo_depth);
    (* prefix = "" *)
    interface SPI_IO#(periph_count) io;
    method bit sb_interrupt;
  endinterface

  (* conflict_free= "rl_transmit_bytes , rl_receive_bytes" *)
  (* descending_urgency= "rl_clr_fifo_async, rl_crc8_management" *)
  (* descending_urgency= "rl_clr_fifo_async, rl_crc16_management" *)
  (* descending_urgency= "rl_clr_fifo_async, rl_handle_cs" *)
  /*doc:module: SPI implementation Module with DCBus Interface and
  the maximum number of peripheral are limited to 8  */
  module [ModWithDCBus#(aw,dw)]  mkspi(Ifc_spi#(periph_count, fifo_depth)) provisos(
      Add#(1 , _a, TLog#(TDiv#(dw, 8)))
    , Add#(dw, _b, 64)
    , Add#(TExp#(TLog#(dw)), 0, dw)
    , Mul#(TDiv#(dw, 8), 8, dw)
    , Add#(a__, TDiv#(dw, 8), 8)
    , Add#(b__, 1, aw)
    , Add#(c__, 2, aw)

    , Add#(d__, 1, periph_count)
    , Add#(e__, TLog#(periph_count), 3)
    , Add#(f__, periph_count, 8) // Limiting to 8 Peripherals

    , Add#(g__, TLog#(TAdd#(fifo_depth, 1)), 8) // can't exceed 255
    , Mul#(fifo_depth, 8, fifo_bit_capacity)
    , Div#(fifo_depth, 2, fifo_hf_depth)
    , Div#(fifo_hf_depth, 2, fifo_qrtr_depth)
    , Add#(fifo_hf_depth, fifo_qrtr_depth, fifo_3_qrtr_depth)
  );

  let bus_clock <- exposeCurrentClock;
  let bus_reset <- exposeCurrentReset;

  SPI_atomic#(8) spi <- mkspi_atom;

  /*doc:note: Variables assoc to internal states */
  Reg#(Cs_state) rg_cs_state      <- mkReg(IDLE);
  Reg#(bit)      rg_ncs           <- mkReg(0);
  Wire#(Bit#(periph_count)) wr_ncs <- mkBypassWire();
  Wire#(Bool)    wr_lsbfirst      <- mkWire;
  Reg#(Bool)     rg_hf_dplx_1st   <- mkReg(False);
  Reg#(bit)      interrupt_signal <- mkReg(0);
  Reg#(Bytebits) rg_rx_cnt        <- mkReg(unpack(0));
  Reg#(Bytebits) rg_tx_cnt        <- mkReg(unpack(0));
  Reg#(CM_mode)  rg_cm_mode       <- mkReg(INVALID);
  Wire#(Bool)    wr_start_xaction <- mkWire();
  PulseWire      xfer_delay       <- mkPulseWire;
  PulseWire      wr_terminate     <- mkPulseWire;
  Reg#(Bool)     stop_spi_imm     <- mkDReg(False);
  Reg#(Bool)     setup_hold_dly   <- mkDReg(False);
  Wire#(Bool)    wr_is_transfer   <- mkWire;
  Wire#(Status_cfg) wr_status     <- mkWire;
  Wire#(bit)     wr_spi_enable    <- mkWire;

  /*doc:note: Variables assoc to Txn State */
  Reg#(Bool)      tx_data_en         <- mkReg(False);
  Reg#(Bit#(2))  rg_txr_byte_count   <- mkReg(0);
  Reg#(Bit#(8))  rg_txfifo_bit_count <- mkReg(0);
  Reg#(Bool)     rg_trigger_tx       <- mkReg(False);
  FIFOCountIfc#(Bit#(8), fifo_depth) tx_fifo  <- mkGFIFOCount(True,True,True);
  Wire#(Bool)     wr_tx_Nempty       <- mkWire;
  Wire#(Bool)     wr_tx_Nfull        <- mkWire;
  Wire#(Bit#(32)) wr_spi_cfg_dr_tx   <- mkWire;

  /*doc:note: Variables assoc to Rxn State */
  Reg#(Bool)      rg_rxne            <- mkReg(False);
  Reg#(Bit#(3))   rg_rxr_byte_count  <- mkReg(0);
  FIFOCountIfc#(Bit#(8), fifo_depth) rx_fifo  <- mkGFIFOCount(True,True,True);
  Wire#(Bool)     wr_rx_Nfull        <- mkWire;
  Wire#(Bool)     wr_rx_Nempty       <- mkWire;
  Wire#(Bit#(32)) wr_spi_cfg_dr_rx   <- mkWire;
  Wire#(Bool)     wr_rx_wm           <- mkWire;


  /*doc: note: Variables assoc to Delay state */
/////////////////// EARMARKED for Setup / Hold / Xfer Delay Handling ///////////
//

  Clock newclock = spi.spi_clk;
  Reset newreset <- mkAsyncReset(0, bus_reset, newclock);
  /* This Register Holds the duration of delay */
  Reg#(Bit#(8)) rg_delay_amt     <- mkReg(0);
  ReadOnly#(Bit#(8)) sync_delay  <- mkNullCrossingWire(newclock, rg_delay_amt);
  /* This register keeps count of delay to reach the spec. rg_delay_amt */
  Reg#(Bit#(8)) rg_delay_counter <- mkRegA(0, clocked_by newclock, reset_by newreset);
  ReadOnly#(Bit#(8)) sync_cnt    <- mkNullCrossingWire(bus_clock, rg_delay_counter);
//
////////////////////////////////////////////////////////////////////////////////

  /*doc:note: Variables assoc to CRC Handling */
  RWire#(Bit#(8)) rwAddIn            <- mkRWire;
  PulseWire       rx_crc_enq         <- mkPulseWire;
  Reg#(Bool)      update_crc_init    <- mkDReg(False);

//
////////////////// EARMARKED for Configuration Registers ///////////////////////
//
  DCRAddr#(aw,2) cfg_cntrl_reg_1 = DCRAddr {addr: 'h00, min: Sz4, max: Sz4, mask: 2'b00};
  Reg#(Control_reg1) rg_spi_cfg_cr1  <- mkDCBRegRW(cfg_cntrl_reg_1, unpack(4));

  DCRAddr#(aw,2) cfg_cntrl_reg_2 = DCRAddr {addr: 'h04, min: Sz4, max: Sz4, mask: 2'b00};
  Reg#(Control_reg2) rg_spi_cfg_cr2  <- mkDCBRegRW(cfg_cntrl_reg_2, unpack(0));

  DCRAddr#(aw,2) spi_en_reg      = DCRAddr {addr: 'h08, min: Sz1, max: Sz4, mask: 2'b00};
  Reg#(Spi_en)   rg_spi_en       <- mkDCBRegRW0Se(spi_en_reg, unpack(0), wr_is_transfer,
  action
    stop_spi_imm <= True;
  endaction );

  DCRAddr#(aw,2) status_reg      = DCRAddr {addr: 'h0C, min: Sz4, max: Sz4, mask: 2'b00};
  Reg#(Status_cfg)    rg_spi_cfg_sr  <- mkDCBRegRO(status_reg , unpack(0));

  DCRAddr#(aw,2) data_reg_tx     = DCRAddr {addr: 'h10, min: Sz4, max: Sz4, mask: 2'b00};
  Reg#(Bit#(32))  rg_spi_cfg_dr_tx   <- mkDCBRegRWSe(data_reg_tx , 'h0, action
    rg_txr_byte_count <= 0; tx_data_en <= True;
  endaction );

  DCRAddr#(aw,2) data_reg_rx     = DCRAddr {addr: 'h14, min: Sz4, max: Sz4, mask: 2'b00};
  Reg#(Bit#(32))  rg_spi_cfg_dr_rx   <- mkDCBRegROSe(data_reg_rx , 'h0, action
    rg_rxr_byte_count <= 0; rg_rxne <= False;
  endaction );

  DCRAddr#(aw,2) cfg_dly_reg     = DCRAddr {addr: 'h20, min: Sz4, max: Sz4, mask: 2'b00};
  Reg#(Delay_cfg) rg_spi_cfg_delay   <- mkDCBRegRW(cfg_dly_reg , unpack(0));

  DCRAddr#(aw,2) prescalar_reg   = DCRAddr {addr: 'h24, min: Sz2, max: Sz4, mask: 2'b00};
  Reg#(Bit#(16)) rg_spi_cfg_prescalar <- mkDCBRegRW(prescalar_reg, 'h4);

  DCRAddr#(aw,2) crc_poly_reg    = DCRAddr {addr: 'h28, min: Sz2, max: Sz4, mask: 2'b00};
  Reg#(Bit#(16)) rg_spi_cfg_crc_poly  <- mkDCBRegRW(crc_poly_reg, 'h4);

  DCRAddr#(aw,2) crc_init_reg    = DCRAddr {addr: 'h2C, min: Sz4, max: Sz4, mask: 2'b00};
  Reg#(Crc_cfg)  rg_spi_cfg_crcpr    <- mkDCBRegRWSe(crc_init_reg, unpack(0), action
    update_crc_init <= True;
  endaction);

  DCRAddr#(aw,2) rx_crc_reg      = DCRAddr {addr: 'h18, min: Sz2, max: Sz4, mask: 2'b00};
  Reg#(Bit#(16))  rg_spi_cfg_rxcrcr  <- mkDCBRegROmask(rx_crc_reg , 'h0, rg_spi_cfg_cr1.crcl,
                      rg_spi_cfg_cr2.crc_ref_out , rg_spi_cfg_crcpr.xor_val );

  DCRAddr#(aw,2) tx_crc_reg      = DCRAddr {addr: 'h1C, min: Sz2, max: Sz4, mask: 2'b00};
  Reg#(Bit#(16))  rg_spi_cfg_txcrcr  <- mkDCBRegROmask(tx_crc_reg , 'h0 , rg_spi_cfg_cr1.crcl,
                      rg_spi_cfg_cr2.crc_ref_out , rg_spi_cfg_crcpr.xor_val );


//
////////////////////////////////////////////////////////////////////////////////
//
  function Action fn_txn_mode(bit is_duplex, bit is_rx_1st);
    action
      if(unpack(is_duplex)) begin
        rg_cm_mode <= DUPLX;
      end
      else begin
        let rx_val = rg_spi_cfg_cr1.total_bit_rx;
        let tx_val = rg_spi_cfg_cr1.total_bit_tx;
        let lv_cm = unpack(is_rx_1st) ? HF_DPLX_RX_1ST : HF_DPLX_TX_1ST;
        lv_cm = case (tuple2 ((rx_val != 0) , (tx_val != 0))) matches
          {True,  True}  : lv_cm          ;
          {False, True}  : SMPLX_TX_ONLY  ;
          {True, False}  : SMPLX_RX_ONLY  ;
          default        : INVALID        ;
        endcase ;
        rg_cm_mode <= lv_cm;
      end
    endaction
  endfunction

  function Bytebits fn_bits_arrange(Bit#(8) val);
    Bool is_unlimited  = (val == '1);
    if(is_unlimited)
      return Bytebits {is_unltd : is_unlimited,
                       bytes    : 0 ,
                       bits     : 0
             };
    else
      return Bytebits {is_unltd : is_unlimited,
                       bytes    : truncate(val >> 3),
                       bits     : truncate(val)
             };
  endfunction

  function Action fn_set_tx_rx(bit is_dplx, Bit#(8) tx_val, Bit#(8) rx_val, Bool is_switch);
    action
      if(unpack(is_dplx)) begin
        Bit#(8) is_max_val = max(tx_val, rx_val);
        rg_rx_cnt <= fn_bits_arrange(is_max_val);
        rg_tx_cnt <= fn_bits_arrange(is_max_val);
      end
      else begin
        if((rg_cm_mode == HF_DPLX_TX_1ST && is_switch) || rg_cm_mode == SMPLX_RX_ONLY ||
          rg_cm_mode == HF_DPLX_RX_1ST && !is_switch)
        begin
          rg_tx_cnt <= fn_bits_arrange(rx_val);
          rg_rx_cnt <= fn_bits_arrange(rx_val);
        end
        else if((rg_cm_mode == HF_DPLX_RX_1ST && is_switch) || rg_cm_mode == SMPLX_TX_ONLY ||
             rg_cm_mode == HF_DPLX_TX_1ST && !is_switch)
        begin
          rg_tx_cnt <= fn_bits_arrange(tx_val);
          rg_rx_cnt <= fn_bits_arrange(0);
        end
      end
    endaction
  endfunction

  (* fire_when_enabled, no_implicit_conditions *)
    /*doc:rule: Ensure that this fires only in controller mode */
  rule rl_delay_counter;
    if(sync_delay == 0)
      rg_delay_counter <= 0;
    else if(sync_delay != rg_delay_counter)
      rg_delay_counter <= rg_delay_counter + 1;
  endrule

    // Rule to reset all state elements on peripheral disable
  rule rl_reset_spi_module( !unpack(rg_spi_en.enable) );
    rg_cs_state <= IDLE;
    rg_ncs      <= 1;
  endrule

  (* fire_when_enabled, no_implicit_conditions *)
  rule assign_wires;
    wr_tx_Nempty <= tx_fifo.notEmpty;
    wr_rx_Nempty <= rx_fifo.notEmpty;
    wr_rx_Nfull  <= rx_fifo.notFull;
    wr_tx_Nfull  <= tx_fifo.notFull;
    wr_is_transfer <= (rg_cs_state == TRANSFER);
    wr_lsbfirst  <= unpack(rg_spi_cfg_cr1.lsbfirst);
  endrule

  (* fire_when_enabled, no_implicit_conditions *)
  rule rl_periph_ncs(unpack(~rg_spi_cfg_cr1.ctrler & rg_spi_en.enable)); // peripheral mode
      Bit#(TLog#(periph_count)) chip_id = truncate(rg_spi_cfg_cr2.periph_selector);
      rg_ncs <= wr_ncs[chip_id] ;
  endrule

  rule rl_update_wr_status;
    let _status_rg = Status_cfg{
          frcnt  : zeroExtend(pack(rx_fifo.count)),
          ftcnt  : zeroExtend(pack(tx_fifo.count)),
          zeros1 : unpack(0),
          ovrf   : ~ pack(wr_tx_Nfull && wr_rx_Nfull),
          bsy    : ~ rg_ncs & pack(rg_cs_state != XFR_DLY),
          modf   : unpack(0),
          crcerr : unpack(0), /*doc:note: update with Appropriate crc_value */
          zeros  : unpack(0),
          txnf   : pack( wr_tx_Nfull),
          rxf    : pack(! wr_rx_Nfull),
          txe    : pack(! tx_data_en),
          rxne   : pack(rg_rxne)
    };
    wr_rx_wm  <= (rx_fifo.count >= ((rg_spi_cfg_cr2.frxth == 1) ?
                                     fromInteger(valueOf(fifo_3_qrtr_depth)) :
                                     fromInteger(valueOf(fifo_hf_depth))));
    wr_status <= _status_rg;
  endrule

  (* fire_when_enabled *)
  rule rl_update_rg_status;
    rg_spi_cfg_sr <= wr_status;
  endrule

  rule rl_clr_fifo_async(unpack(~rg_spi_en.enable & rg_spi_cfg_cr1.clr_fifo));
    rg_ncs      <= 1;
    rg_cs_state <= IDLE;
    update_crc_init <= True; // Initialize CRC with initVal
    tx_fifo.clear();
    rx_fifo.clear();
    rg_rxne <= False;
    rg_trigger_tx <= False;
    rg_spi_cfg_dr_rx <= 0;
    rg_rxr_byte_count <= 0;
    rg_spi_cfg_cr1.clr_fifo <= 0;
    spi.inp.spi_en(False);
    spi.inp.free_run_clk(False);
    `logLevel( spi, 0, $format(" SPI : FIFO is cleared."))
  endrule

  rule rl_set_spi_params(!unpack(rg_spi_en.enable));
    spi.inp.set_mode_lsb({rg_spi_cfg_cr1.cpol, rg_spi_cfg_cr1.cpha}, rg_spi_cfg_cr1.lsbfirst,
                                                                     rg_spi_cfg_cr1.ctrler);
    if(unpack(rg_spi_cfg_cr1.ctrler)) begin
      spi.inp.spi_prescalar(rg_spi_cfg_prescalar);
    end
    fn_txn_mode(rg_spi_cfg_cr1.duplex, rg_spi_cfg_cr1.is_rx_first);
    fn_set_tx_rx(rg_spi_cfg_cr1.duplex, rg_spi_cfg_cr1.total_bit_tx, rg_spi_cfg_cr1.total_bit_rx, False);
    rg_hf_dplx_1st <= False;
  endrule

  rule rl_track_tx_fifo(unpack(rg_spi_en.enable));
    let ctrlr = rg_spi_cfg_cr1.ctrler;
    Bool txn_en = unpack(ctrlr | (~ctrlr & ~rg_ncs));
    if(rg_cm_mode == DUPLX || rg_cm_mode == SMPLX_TX_ONLY || rg_cm_mode == HF_DPLX_TX_1ST) begin
      wr_start_xaction <= rg_trigger_tx && txn_en;
    end else begin
      wr_start_xaction <= (rg_cm_mode != INVALID) && txn_en;
    end
  endrule

  // Handle CS States
  rule rl_handle_cs(unpack(rg_spi_en.enable));
    Bool is_controller = unpack(rg_spi_cfg_cr1.ctrler);
    if(rg_cs_state == IDLE && wr_start_xaction) begin
      if(unpack(rg_spi_cfg_delay.setup_delay_en) && is_controller) begin
        spi.inp.free_run_clk(unpack(rg_spi_cfg_delay.clk_src));
        rg_cs_state  <= STUP_DLY;
        setup_hold_dly <= True;
      end
      else begin
        rg_cs_state <= TRANSFER;
        spi.inp.free_run_clk(False);
      end
      if(is_controller)
        rg_ncs          <= 0;
        spi.inp.spi_en(True);
      end
      else if(rg_cs_state == STUP_DLY) begin
        if(setup_hold_dly)
          rg_delay_amt   <= rg_spi_cfg_delay.setup_delay;
        else if(rg_delay_amt == sync_cnt) begin
          rg_delay_amt <= 0;
          rg_cs_state  <= TRANSFER;
          spi.inp.free_run_clk(False);
        end
        //else begin
        //  rg_delay_amt <= rg_spi_cfg_delay.setup_delay;
        //end
      end
      else if(rg_cs_state == TRANSFER) begin
        if(xfer_delay && is_controller) begin
          spi.inp.free_run_clk(unpack(rg_spi_cfg_delay.clk_src));
          rg_cs_state <= XFR_DLY;
          setup_hold_dly <= True;
        end
        else if(wr_terminate) begin
          if(unpack(rg_spi_cfg_delay.hold_delay_en) && is_controller) begin
            spi.inp.free_run_clk(unpack(rg_spi_cfg_delay.clk_src));
            rg_cs_state <=  HLD_DLY;
            setup_hold_dly <= True;
          end
        else begin
          rg_cs_state <=  INVALID;
        end
      end
      /*doc:note: if ncs goes high terminate transaction in peripheral mode */
      else if(!is_controller && unpack(rg_ncs)) begin
        rg_cs_state   <= REMNANT;
        spi.inp.read_remnant;
      end
    end
    else if(rg_cs_state == XFR_DLY) begin
      if(setup_hold_dly)
        rg_delay_amt <= rg_spi_cfg_delay.xfer_delay;
      else if(rg_delay_amt == sync_cnt) begin
        rg_delay_amt <= 0;
        rg_ncs       <= 0;
        rg_cs_state  <= TRANSFER;
        spi.inp.free_run_clk(False);
      end
      else begin
        //rg_delay_amt <= rg_spi_cfg_delay.xfer_delay;
        rg_ncs       <= rg_spi_cfg_cr2.ncsp;
      end
    end
    else if(rg_cs_state == HLD_DLY) begin
      if(setup_hold_dly)
        rg_delay_amt   <= rg_spi_cfg_delay.hold_delay;
      else if(rg_delay_amt == sync_cnt) begin
        rg_delay_amt     <= 0;
        rg_cs_state      <= IDLE;
        rg_ncs           <= 1;
        wr_spi_enable    <= 0;
        spi.inp.spi_en(False);
        spi.inp.free_run_clk(False);
      end
      //else begin
      //  rg_delay_amt <= rg_spi_cfg_delay.hold_delay;
      //end
    end
    else if(rg_cs_state == IDLE && !wr_start_xaction) begin // Keep waiting for xaction to go high.
      noAction;
    end
    else if(rg_cs_state == REMNANT) begin
      if(spi.inp.remnant_complete)
      rg_cs_state <= INVALID;
    end
    else begin // reaches on INVALID case
      if(is_controller)
        rg_ncs           <= 1;
      rg_cs_state        <= IDLE;
      wr_spi_enable      <= 0;
      spi.inp.spi_en(False);
      spi.inp.free_run_clk(False);
    end
  endrule

  rule rl_terminate_spi(unpack(rg_spi_en.enable));
    if(stop_spi_imm) begin
      if(rg_cs_state != TRANSFER)
        wr_terminate.send;
      else begin
        if(spi.inp.is_idle || !unpack(rg_spi_cfg_cr1.spi_dis_sync))
          wr_terminate.send;
        else
          stop_spi_imm <= True;
      end
    end
  endrule

  rule rl_disable_spi;
    rg_spi_en.enable <= wr_spi_enable ;
  endrule

  rule rl_transmit_bytes(unpack(rg_spi_en.enable) && rg_cs_state == TRANSFER && spi.inp.is_idle);

    /* in Duplex case if any of the fifo's fail stop transaction) */
    let is_dplx_case    = rg_cm_mode == DUPLX && wr_tx_Nempty && wr_rx_Nfull ;

    /* in Simplex case if appropriate fifo fails stop transaction */
    let is_smplx_case   = ((rg_cm_mode == SMPLX_TX_ONLY && wr_tx_Nempty) ||
                 (rg_cm_mode == SMPLX_RX_ONLY && wr_rx_Nfull ));

    /* In half duplex based on switch case if appropriate fifo fails stop transaction */
    let is_hf_dplx_case = (((!rg_hf_dplx_1st && wr_tx_Nempty) || (rg_hf_dplx_1st && wr_rx_Nfull))
     && (rg_cm_mode == HF_DPLX_TX_1ST)) || ((rg_cm_mode == HF_DPLX_RX_1ST) &&
      ((!rg_hf_dplx_1st && wr_rx_Nfull ) || (rg_hf_dplx_1st && wr_tx_Nempty)));

    /* In Half duplex switch based on limited or unlimited scenarios*/
    let unltd_switch = ((rg_cm_mode == HF_DPLX_TX_1ST && !wr_tx_Nempty ) ||
              (rg_cm_mode == HF_DPLX_RX_1ST && !wr_rx_Nfull  ));
    let is_hf_switch_case = ( !rg_hf_dplx_1st && ((rg_tx_cnt.is_unltd && unltd_switch)    ||
            ((!rg_tx_cnt.is_unltd && rg_tx_cnt.bytes == 0 && rg_tx_cnt.bits == 0) &&
             (rg_cm_mode == HF_DPLX_TX_1ST || rg_cm_mode == HF_DPLX_RX_1ST))));

    Bool is_valid = rg_tx_cnt.is_unltd && (is_dplx_case || is_smplx_case || is_hf_dplx_case);
    /* doc:note: in HF_DPLX_RX_1ST, tx_fifo will not be empty and that should not be transmitted
    in first half of transaction, below wire fixes this */
    Bool ff_data_val = !(rg_cm_mode == HF_DPLX_RX_1ST && !rg_hf_dplx_1st) && wr_tx_Nempty ;
    Bit#(8) tx_byte = (ff_data_val) ? tx_fifo.first : signExtend(rg_spi_cfg_cr2.idle_out) ;
    if((rg_tx_cnt.bytes != 0 || rg_tx_cnt.bits != 0)) begin
      Bit#(4) pkt_sz  = 8;
      let upd_tx_cnt  = rg_tx_cnt;
      if(rg_tx_cnt.bytes != 0) begin
        upd_tx_cnt.bytes  = rg_tx_cnt.bytes - 1 ;
      end
      else if(rg_tx_cnt.bits != 0) begin
        pkt_sz = zeroExtend(rg_tx_cnt.bits);
        upd_tx_cnt.bits = 0;
      end
      spi.inp.put_byte(tx_byte,  pkt_sz);
      rg_tx_cnt <= upd_tx_cnt;
      if(ff_data_val)
        tx_fifo.deq;
    end
    else if(is_valid ) begin
      if(ff_data_val)
        tx_fifo.deq;
      spi.inp.put_byte(tx_byte,  8);
    end
    else if(is_hf_switch_case) begin
      if(unpack(rg_spi_cfg_delay.xfer_delay_en)) begin
        xfer_delay.send;
      end
      rg_hf_dplx_1st <= True;
      fn_set_tx_rx(rg_spi_cfg_cr1.duplex, rg_spi_cfg_cr1.total_bit_tx, rg_spi_cfg_cr1.total_bit_rx, True);
    end
    else begin
      if(unpack(rg_spi_cfg_cr1.ctrler)) begin
        stop_spi_imm <= True;
      end else begin /* doc: note: As peripheral shouldn't stop communication send dummy byte */
        spi.inp.put_byte(tx_byte,  8);
      end
    end
  endrule

  // Handle received data
  rule rl_receive_bytes(unpack(rg_spi_en.enable) && (rg_cs_state == TRANSFER || rg_cs_state == REMNANT)) ;
    let lv_rx_val <- spi.inp.get_byte;
    Bool is_enqueue = wr_rx_Nfull;
    let upd_cnt = rg_rx_cnt;
    if(rg_rx_cnt.bytes != 0 || rg_rx_cnt.bits != 0) begin
      if(rg_rx_cnt.bytes != 0) begin
        upd_cnt.bytes =  rg_rx_cnt.bytes - 1;
      end
      else if(rg_rx_cnt.bits != 0) begin
        let mask = (1 << rg_rx_cnt.bits) - 1;
        Bit#(4) sh_amt = 8 - zeroExtend(rg_rx_cnt.bits);
        let mask_val = wr_lsbfirst ? (mask) : (mask << sh_amt);
        lv_rx_val = lv_rx_val & mask_val ;
        upd_cnt.bits = 0;
      end
      if(is_enqueue) begin
        rx_crc_enq.send;
        rx_fifo.enq(lv_rx_val);
        rwAddIn.wset(lv_rx_val);
      end
      rg_rx_cnt <= upd_cnt;
    end
    else if(rg_rx_cnt.is_unltd && wr_rx_Nfull) begin // unlimited receive
      if(is_enqueue) begin
        rx_crc_enq.send;
        rx_fifo.enq(lv_rx_val);
        rwAddIn.wset(lv_rx_val);
      end
    end
  endrule

  /*doc:rule:
     ************** TRANSMIT STATE *******************
   * This rule takes data from the configration register
   * DR and puts it into the tx_fifo in the 8 bit format
   */
  rule rl_transmit_data_to_fifo(tx_data_en);
    if(tx_fifo.notFull) begin
      Bit#(8) data = 0;

      /*doc:note: Arrange data for FIFO according to the MSB/LSB Format */
      if(wr_lsbfirst) begin
        data = rg_spi_cfg_dr_tx[7 : 0];
        wr_spi_cfg_dr_tx <= rg_spi_cfg_dr_tx >> 8;
      end
      else begin
        data = rg_spi_cfg_dr_tx [31: 24];
        wr_spi_cfg_dr_tx <= rg_spi_cfg_dr_tx << 8;
      end

      /*doc:note: Disable Write beyond 32-bit, if the reg is not rewritten
       * Disable Write if 'total_bit_tx' number of bits are enqueued
       */
      if((rg_txr_byte_count == 3) || !((rg_txfifo_bit_count + 8) < rg_spi_cfg_cr1.total_bit_tx)) begin
        `logLevel( spi, 2, $format(" SPI : rl_transmit_data_to_fifo - Disabling Rule "))
        tx_data_en <= False;
      end
      else begin
        rg_txr_byte_count <= rg_txr_byte_count + 1;
      end

      /*doc:note: Enqueue data according to the user setting of 'total_bit_tx'
       * Data will be enqueued in terms of bytes
       *
       * For example even if the 'total_bit_tx' = 10 the data
       * 0:7 8;15 are enqueued into FIFO. While transmittiing to output line
       * after 10th bit the data in FIFO will be discarded
       */
      if(rg_txfifo_bit_count < rg_spi_cfg_cr1.total_bit_tx) begin
        tx_fifo.enq(data);
        rwAddIn.wset(data); // Add the same data to CRC
        `logLevel( spi, 2, $format(" SPI : Tx Reg to tx_fifo \t data: %x \t \
        Bits Transferred: %d \t rg_spi_tx: %x ", data, rg_txfifo_bit_count+8, rg_spi_cfg_dr_tx))
      end

      /*doc:note: Initiate settings for Transmission
       * If the data to be transmitted is less than FIFO capacity
       *      Hold the entire data in FIFO (until reaches spec. total_bit_tx)
       *      Initiate Transaction immediately on Tx fill.
       * Else wait till Half of the FIFO is filled & Transmit
       *      Initiate Transaction
       */
      if(rg_spi_cfg_cr1.total_bit_tx <= fromInteger(valueOf(fifo_bit_capacity))) begin
        if((rg_spi_cfg_cr1.total_bit_tx <= (rg_txfifo_bit_count +8)) && rg_cs_state == IDLE )
        begin
          rg_txfifo_bit_count <= 0;
          rg_trigger_tx <= True;
          `logLevel( spi, 1, $format(" SPI : rl_transmit_data_to_fifo \
            - %d bytes of FIFO is filled ",tx_fifo.count))
        end
        else begin
          rg_txfifo_bit_count <= (rg_txfifo_bit_count + 8) ;
        end
      end
      else begin
        if(tx_fifo.count > fromInteger(valueOf(fifo_hf_depth)) && rg_cs_state == IDLE) begin
          `logLevel( spi, 1, $format(" SPI : rl_transmit_data_to_fifo \
            - %d bytes of FIFO is filled ",tx_fifo.count))
          rg_trigger_tx <= True;
        end
      end
    end
    else begin
      `logLevel( spi, 0, $format("SPI OVERFLOW DETECTED: The data written \
        to Tx Reg hasn't been enqueued."))
    end
  endrule

  rule rl_persist_tx_register;
    rg_spi_cfg_dr_tx <= wr_spi_cfg_dr_tx;
  endrule

  /*doc:rule: rule that pushes data from FIFO to RxR register
  This rule should be fired to flush out
  1. remnant data once spi is disabled
  2. fifo residing data in word format */
  rule rl_receive_fifo_to_read_datareg(! rg_rxne );
    /* doc:note: If in controller mode, flush out when spi gets disabled.
    If in peripheral mode, rely on rg_rx_cnt variables. */
    let remnant_cond = ((rg_spi_cfg_cr1.ctrler == 0) && !rg_rx_cnt.is_unltd
                       && rg_rx_cnt.bytes == 0 && rg_rx_cnt.bits == 0) || !unpack(rg_spi_en.enable);

    if(wr_rx_Nempty && rg_rxr_byte_count < 4) begin // Wait for the reg to get read.
      let data = rx_fifo.first();
      Bit#(32) data_reg = 0;
      if(wr_lsbfirst) begin
        data_reg = case (rg_rxr_byte_count)
          0: return zeroExtend(data);
          1: return zeroExtend(data) << 8 ;
          2: return zeroExtend(data) << 16;
          3: return zeroExtend(data) << 24;
        endcase;
      end
      else begin
        data_reg = case (rg_rxr_byte_count)
          0: return zeroExtend(data) << 24;
          1: return zeroExtend(data) << 16;
          2: return zeroExtend(data) << 8 ;
          3: return zeroExtend(data);
        endcase;
      end
      wr_spi_cfg_dr_rx  <= (rg_rxr_byte_count == 0) ? data_reg : (rg_spi_cfg_dr_rx | data_reg) ;
      rg_rxr_byte_count <= rg_rxr_byte_count + 1;
      if(rg_rxr_byte_count == 3 )
        rg_rxne <= True;
      `logLevel( spi, 1, $format(" SPI : Transferring data from rx_fifo to dr reg %x \t %x \
        at slot %d",data,data_reg,rg_rxr_byte_count))
      rx_fifo.deq();
    end
    else if(!wr_rx_Nempty && rg_rxr_byte_count != 0 && remnant_cond) begin // flush out remnant data
      rg_rxne <= True;
    end
  endrule

  rule rl_drive_rx_register;
    rg_spi_cfg_dr_rx <= wr_spi_cfg_dr_rx;
  endrule

  rule rl_interrupt_managment;
    interrupt_signal <= ((rg_spi_en.enable & rg_spi_cfg_cr2.txeie  & rg_spi_cfg_sr.txe ) |
               (rg_spi_cfg_cr2.rxneie & rg_spi_cfg_sr.rxne) |
               (rg_spi_cfg_cr2.wmie   & pack(wr_rx_wm))     |
               (rg_spi_cfg_cr2.errie  & rg_spi_cfg_sr.ovrf));
  endrule
//
///////////////////////// EARMARKED FOR CRC OPERATIONS /////////////////////////
//

  function Bit#(a) reflect(bit doIt, Bit#(a) data);
    return (unpack(doIt)) ? reverseBits(data) : data;
  endfunction

  rule rl_crc8_management(rg_spi_cfg_cr1.crcen == 1 && rg_spi_cfg_cr1.crcl == 0); //crc8.
    if (update_crc_init) begin
      Bit#(8) initial_val = truncate(rg_spi_cfg_crcpr.initval);
      rg_spi_cfg_txcrcr  <= zeroExtend(initial_val);
      rg_spi_cfg_rxcrcr  <= zeroExtend(initial_val);
    end
    else if (rwAddIn.wget matches tagged Valid .data) begin
      Bit#(8) prev_rm = (rx_crc_enq) ? truncate(rg_spi_cfg_rxcrcr) : truncate(rg_spi_cfg_txcrcr);
      Bit#(8) remainder = prev_rm ^ reflect(rg_spi_cfg_cr2.crc_ref_in, data);
      for(Integer i = 0; i < 8; i = i + 1) begin
        let rem_1 = remainder << 1 ;
         remainder = (msb(remainder) == 1) ? (rem_1 ^ truncate(rg_spi_cfg_crc_poly)) : rem_1;
//  remainder = (lsb(remainder) == 1) ? (rem_1 ^ reflect(lsbfirst, rg_spi_cfg_crc_poly): rem_1;
      end
      `logLevel( spi, 2, $format(" SPI CRC : CRC Value %x",remainder))
      if(rx_crc_enq)
        rg_spi_cfg_rxcrcr <= zeroExtend(remainder);
      else
        rg_spi_cfg_txcrcr <= zeroExtend(remainder);
    end
  endrule

  rule rl_crc16_management(rg_spi_cfg_cr1.crcen == 1 && rg_spi_cfg_cr1.crcl == 1); //crc16.
    if (update_crc_init) begin
      rg_spi_cfg_txcrcr  <= zeroExtend(rg_spi_cfg_crcpr.initval);
      rg_spi_cfg_rxcrcr  <= zeroExtend(rg_spi_cfg_crcpr.initval);
    end
    else if (rwAddIn.wget matches tagged Valid .data) begin
      Bit#(16) prev_rm = (rx_crc_enq) ? truncate(rg_spi_cfg_rxcrcr) : truncate(rg_spi_cfg_txcrcr) ;
      Bit#(16) remainder = prev_rm ^ (zeroExtend(reflect(rg_spi_cfg_cr2.crc_ref_in, data)) << valueOf(8));
      for(Integer i = 0; i < 8; i = i + 1) begin
         let rem_1 = remainder << 1 ;
         remainder = (msb(remainder) == 1) ? (rem_1 ^ truncate(rg_spi_cfg_crc_poly)) : rem_1;
//  remainder = (lsb(remainder) == 1) ? (rem_1 ^ reflect(lsbfirst, rg_spi_cfg_crc_poly): rem_1;
    end
    `logLevel( spi, 2, $format(" SPI CRC : CRC Value %x",remainder))
    if(rx_crc_enq)
      rg_spi_cfg_rxcrcr <= zeroExtend(remainder);
    else
      rg_spi_cfg_txcrcr <= zeroExtend(remainder);
    end
  endrule
//
////////////////////////////////////////////////////////////////////////////////
//

  interface io = interface SPI_IO
    interface copi = spi.io.copi;
    interface cipo = spi.io.cipo;
    interface sclk = spi.io.sclk;
    interface ncs  = interface Tri_state
      method Action in(Bit#(periph_count) ncs) ;
        wr_ncs <= ncs;
      endmethod
      method bit out_en;
        return rg_spi_cfg_cr1.ctrler;
      endmethod
      method Bit#(periph_count) out ;
        Bit#(periph_count) _ncs_temp = '1;
        Bit#(TLog#(periph_count)) periph_id = truncate(rg_spi_cfg_cr2.periph_selector);
        _ncs_temp[periph_id] = rg_ncs;
        return _ncs_temp;
      endmethod
    endinterface;
  endinterface;

  method bit sb_interrupt;
    return interrupt_signal;
  endmethod

endmodule // SPI

  module [Module] mk_spi_block#(Clock spi_clk, Reset spi_rst)
    (IWithDCBus#(DCBus#(aw,dw), Ifc_spi#(periph_count, fifo_depth)))  provisos(
      Add#(1 , _a, TLog#(TDiv#(dw, 8)))
    , Add#(dw, _b, 64)
    , Add#(TExp#(TLog#(dw)), 0, dw)
    , Mul#(TDiv#(dw, 8), 8, dw)
    , Add#(a__, TDiv#(dw, 8), 8)
    , Add#(b__, 1, aw)
    , Add#(c__, 2, aw)

    , Add#(d__, 1, periph_count)
    , Add#(e__, TLog#(periph_count), 3)
    , Add#(f__, periph_count, 8)

    , Add#(g__, TLog#(TAdd#(fifo_depth, 1)), 8)
    , Mul#(fifo_depth, 8, fifo_bit_capacity)
    , Div#(fifo_depth, 2, fifo_hf_depth)
    );
    let ifc <- exposeDCBusIFC(mkspi());
    return ifc;
  endmodule:mk_spi_block

  module [Module] mkspi_axi4l#(parameter Integer base, Clock spi_clk, Reset spi_rst)
    (Ifc_spi_axi4l#(aw, dw, uw, periph_count,fifo_depth)) provisos(
      Add#(1 , _a, TLog#(TDiv#(dw, 8)))
    , Add#(dw, _b, 64)
    , Add#(TExp#(TLog#(dw)), 0, dw)
    , Mul#(TDiv#(dw, 8), 8, dw)
    , Add#(a__, TDiv#(dw, 8), 8)
    , Add#(b__, 1, aw)
    , Add#(c__, 2, aw)

    , Add#(d__, 1, periph_count)
    , Add#(e__, TLog#(periph_count), 3)
    , Add#(f__, periph_count, 8)

    , Add#(g__, TLog#(TAdd#(fifo_depth, 1)), 8)
    , Mul#(fifo_depth, 8, fifo_bit_capacity)
    , Div#(fifo_depth, 2, fifo_hf_depth)
    );

    let device = mk_spi_block( spi_clk, spi_rst);
    Ifc_spi_axi4l#(aw, dw, uw, periph_count, fifo_depth) spi <- dc2axi4l(device, base, spi_clk, spi_rst);
    return spi;
  endmodule:mkspi_axi4l

  module [Module] mkspi_apb#( parameter Integer base, Clock spi_clk, Reset spi_rst)
    (Ifc_spi_apb#(aw, dw, uw, periph_count, fifo_depth)) provisos(
      Add#(1 , _a, TLog#(TDiv#(dw, 8)))
    , Add#(dw, _b, 64)
    , Add#(TExp#(TLog#(dw)), 0, dw)
    , Mul#(TDiv#(dw, 8), 8, dw)
    , Add#(a__, TDiv#(dw, 8), 8)
    , Add#(b__, 1, aw)
    , Add#(c__, 2, aw)

    , Add#(d__, 1, periph_count)
    , Add#(e__, TLog#(periph_count), 3)
    , Add#(f__, periph_count, 8)

    , Add#(g__, TLog#(TAdd#(fifo_depth, 1)), 8)
    , Mul#(fifo_depth, 8, fifo_bit_capacity)
    , Div#(fifo_depth, 2, fifo_hf_depth)
    );

    let device = mk_spi_block( spi_clk, spi_rst);
    Ifc_spi_apb#(aw, dw, uw, periph_count, fifo_depth) spi <- dc2apb(device, base, spi_clk, spi_rst);
    return spi;
  endmodule:mkspi_apb
endpackage
