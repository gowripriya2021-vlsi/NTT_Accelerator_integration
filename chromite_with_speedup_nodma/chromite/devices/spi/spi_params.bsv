// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd.
// See LICENSE.incore for More details
/*--------------------------------------------------------------------------------------------------
    Author: Babu P S
    Email id: info@incoresemi.com
--------------------------------------------------------------------------------------------------*/

package spi_params;

    import DCBus        :: *;
    import Vector       :: *;
    import Reserved     :: *;

    typedef struct {
        Bool is_unltd;
        Bit#(5)   bytes;
        Bit#(3)   bits;
    } Bytebits deriving (Bits, Eq);

    typedef enum { SMPLX_TX_ONLY, SMPLX_RX_ONLY,
                   HF_DPLX_TX_1ST, HF_DPLX_RX_1ST,
                   DUPLX, INVALID } CM_mode deriving (Bits, Eq);

    typedef enum { IDLE,
                   STUP_DLY,
                   TRANSFER,
                   XFR_DLY,
                   HLD_DLY,
                   REMNANT,
                   INVALID } Cs_state deriving(Bits,Eq);

    typedef struct{
        Bit#(8)  total_bit_rx;      // Data frame size to choose upto 255 bits
        Bit#(8)  total_bit_tx;      //                "
        bit      spi_dis_sync;      // Disable the SPI Peripheral sync(1) / async(0)
        bit      duplex;            // Simplex (0) / Duplex (1)
        bit      crcen;             // CRC Check Enable
        bit      crcl;              // 8-bit (0) / 16-bit (1) CRC length
        ReservedZero#(1) zeros3;
        bit      clr_fifo;          // Clear the internal fifo.
        ReservedZero#(1) ssm;       // SS Management enabled (1) / disabled (0)
        ReservedZero#(1) ssi;       // SS input
        bit      lsbfirst;          // LSB (1) / MSB(0) first
        bit      is_rx_first;       // when duplex = 0 and (rx_bits & tx_bits != 0) this bit decides who transfer first
        ReservedZero#(1) zeros2;
        ReservedZero#(1) zeros1;
        ReservedZero#(1) zeros;
        bit      ctrler;       // Controller(1) / Peripheral(0) configuration
        bit      cpol;              // Clock Polarity (0) / (1)  when idle
        bit      cpha;              // Clock Phase first (0) / second (1) clock transtion for data capture
    } Control_reg1 deriving(Bits, Eq, Bounded, FShow);

    typedef struct{
        ReservedZero#(5) zeros3;    // Reserved
        Bit#(3)  periph_selector;   // Peripheral Selector Limited to maximum of 8
        ReservedZero#(2) zeros2;
        ReservedZero#(1) crcnext;   // Next Transmit value from Tx_CRC (0) / Rx_CRC(1) Buffer
        ReservedZero#(1) crc_send;  // Send CRC value after transaction - Resets to zero on enqueue.
        ReservedZero#(2) zeros1;
        bit      crc_ref_out;       // Reflect the CRC output - check www.crccalc.com for more info
        bit      crc_ref_in;        // Reflect the data fed for CRC
        ReservedZero#(1) zeros;
        ReservedZero#(1) ldma_tx;   // Last DMA transfer for Tx
        ReservedZero#(1) ldma_rx;   // Last DMA transfer for Rx
        bit      frxth;             // RX FIFO Threshold Half(0) / 3 Quarter (1)
        ReservedZero#(4) ds;        // Data Frame Size. (4 -> 16 bit)
        bit      txeie;             // Enable interrupt for TXFIFO when emptied
        bit      rxneie;            // Enable interrupt for RXFIFO when filled
        bit      errie;             // Over-run error interrupt mask
        bit      wmie;              // Enable Interrupt for frxth
        bit      idle_out;          // idle mode byte filler during transfer
        bit      ncsp;              // NCS pulse during Inter transfer delays
        ReservedZero#(1) txdmaen;   // Tx Buffer DMA enabled (1) / disabled (0)
        ReservedZero#(1) rxdmaen;   // Rx Buffer DMA enabled (1) / disabled (0)
    } Control_reg2 deriving(Bits, Eq, FShow);

    typedef struct{
        ReservedZero#(7) zeros;
        bit     enable;
    } Spi_en deriving(Bits, Eq, FShow);

    typedef struct{
        Bit#(8)  frcnt; // Unread data bytes in FIFO
        Bit#(8)  ftcnt; // Non-transmitted bytes in FIFO
        ReservedZero#(4) zeros1; // reserved
        bit      bsy;            // SPI Bus Status - Data transfer in progress
        bit      ovrf;           // Overrun Flag - Data more than FIFO can hold had been sent / Received.
        ReservedZero#(1) modf;   // Mode fault
        ReservedZero#(1) crcerr; // CRC Error
        ReservedZero#(4) zeros;  // reserved
        bit      txnf;           // Tx FIFO Not Full (Fill the fifo until this goes zero)
        bit      rxf;            // RX FIFO Full
        bit      txe;            // Tx Reg is Empty ( Read to load when this is one )
        bit      rxne;           // Rx Reg is not Empty ( Ready to read when this is one )
    } Status_cfg deriving(Bits, Eq, FShow);

    typedef struct{
        Bit#(8) xfer_delay;       // 8-bit delay
        Bit#(8) hold_delay;       // 8-bit delay
        Bit#(8) setup_delay;      // 8-bit delay
        ReservedZero#(4) zeros3;  // reserved
        bit     xfer_delay_en;    // delay between Transfers
        bit     hold_delay_en;    // Hold delay
        bit     setup_delay_en;   // Setup delay
        bit     clk_src;          // clk_src
    } Delay_cfg deriving(Bits, Eq, FShow);

    typedef struct{
        Bit#(16) xor_val;         // 16-bit Initial Val
        Bit#(16) initval;      // 16-bit Polynomial Val
    } Crc_cfg deriving(Bits, Eq, FShow);

// Reg with side effect on writing zero
// Action on Read : None
// Action on Write : Yes (Only on Writing a zero to bit 0)
// Condition on Read : None
// Condition on Write : None
//----------------------------------------------------------------------------------------------------------------

module regRW0Se#(DCRAddr#(aw,o) attr, Spi_en reset, Bool a, Action _act)(IWithDCBus#(DCBus#(aw, dw), Reg#(Spi_en)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(e__, TDiv#(dw, 8), 8)
  );

  Reg#(Spi_en) x();
  mkReg#(reset) inner_reg(x);
  PulseWire written <- mkPulseWire;

  interface DCBus dcbus;
    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
      if ((req_index == reg_index) && perm) begin
        let {succ, temp} <- fn_adjust_write(addr, data, strobe, pack(x), attr.min, attr.max, attr.mask);
        if(succ) begin
        if(temp[0] == 0 && a) begin
            _act;
            temp[0] = 1;
        end
        x<= unpack(temp);
        written.send;
        end // give cbus write priority over device _write.
        return succ;
      end
      else
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
      if ((req_index == reg_index) && perm) begin
        let temp = fn_adjust_read(addr, size, pack(x), attr.min, attr.max, attr.mask );
        return temp;
      end
      else
        return tuple2(False, 0);
    endmethod:read
  endinterface:dcbus

  interface Reg device;
    method Action _write (value);
      if (!written) x <= value;
    endmethod:_write

    method _read = x._read;
  endinterface
endmodule:regRW0Se

module [ModWithDCBus#(aw, dw)] mkDCBRegRW0Se#(DCRAddr#(aw,o) attr, Spi_en x, Bool a, Action _act)(Reg#(Spi_en))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(e__, TDiv#(dw, 8), 8)
  );
  let ifc();
  collectDCBusIFC#(regRW0Se(attr, x, a, _act)) _temp(ifc);
  return(ifc);
endmodule:mkDCBRegRW0Se

// ------------------------------ Read-Only register with mask value -------------------------------
module regROmask#(DCRAddr#(aw,o) attr, Bit#(16) reset, bit crcl, bit refl, Bit#(16) mask)(IWithDCBus#(DCBus#(aw, dw), Reg#(Bit#(16))))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw),   // bus-side data-width should be multiples of 8
    Add#(dw, b__, 64),           // bus side data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(e__, TDiv#(dw, 8), 8)
    //Bits#(r, m), Bitwise#(r),
    //Add#(hf, 8, m),
    //Mul#(TDiv#(m, 8), 8, m),     // register data-width should be multiples of 8
    //Add#(m, c__, 64),            // register data should be <= 64
    //Add#(TExp#(TLog#(m)),0,m),   // register side should be a power of 2
  );

  Reg#(Bit#(16)) x();
  mkReg#(reset) inner_reg(x);

  function Bit#(16) crc_format(bit crcl, bit refl, Bit#(16) mask, Bit#(16) rval);
    if(crcl == 1) begin
      Bit#(16) ref_val = (unpack(refl)) ? reverseBits(rval) : rval;
      return (ref_val ^ mask);
    end else begin
      Bit#(8) data = truncate(rval);
      Bit#(8) ref_val = (unpack(refl)) ? reverseBits(data) : data;
      return zeroExtend(ref_val ^ truncate(mask));
    end
  endfunction:crc_format

  interface DCBus dcbus;

    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
      return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
      if ((req_index == reg_index) && perm) begin
        let y = crc_format(crcl, refl, mask, x);
        return fn_adjust_read(addr, size, pack(y), attr.min, attr.max, attr.mask );
      end
      else
        return tuple2(False, 0);
    endmethod:read
  endinterface:dcbus

  interface Reg device;
    method Action _write (value);
      x <= value;
    endmethod:_write

    method _read = x._read ;
  endinterface
endmodule:regROmask

// A wrapper to provide just a normal Reg interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal register would be used).
module [ModWithDCBus#(aw, dw)] mkDCBRegROmask#(DCRAddr#(aw,o) attr, Bit#(16) x, bit crcl, bit refl, Bit#(16) mask)(Reg#(Bit#(16)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(e__, TDiv#(dw, 8), 8)
    //Bits#(r, m), Bitwise#(r),
    //Add#(f__, 8, m),
    //Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    //Add#(m, c__, 64),  // register data should be <= 64
    //Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
  );
  let ifc();
  collectDCBusIFC#(regROmask(attr, x, crcl, refl, mask )) _temp(ifc);
  return(ifc);
endmodule:mkDCBRegROmask
// ------------------------------------------------------------------------------------------------

endpackage:spi_params
