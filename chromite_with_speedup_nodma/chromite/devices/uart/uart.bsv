// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details.
/*
Author: Arjun Menon
E-mail: arjun@incoresemi.com
Description: UART
*/
package uart;
  import GetPut::*;
  import FIFO::*;
  import ConfigReg::*;
  import Clocks::*;
  import BUtils::*;
  import DefaultValue::*;
  import ModuleCollect::*;
  import Vector::*;
  import Reserved :: *;

  `include "Logger.bsv"       // for logging display statements.
  import axi4::*;
  import axi4l::*;
  import apb::*;
  import Semi_FIFOF::*;
  import RS232_modified::*;
  import DCBus::*;

  export RS232             (..);
  export Ifc_uart          (..);
  export Ifc_uart_axi4l    (..);
  export Ifc_uart_apb      (..);
  export mkuart_axi4l;
  export mkuart_apb;
  export mkuart_block;
  
  interface Ifc_uart#(numeric type depth);
    interface RS232#(depth) io;
    method Bit#(1) interrupt;
  endinterface

  typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw), Ifc_uart#(depth))
      Ifc_uart_axi4l#(type aw, type dw, type uw, numeric type depth);
  typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Ifc_uart#(depth))
      Ifc_uart_apb#(type aw, type dw, type uw, numeric type depth);
  /*typedef IWithSlave#(Ifc_axi4_slave#(iw, aw, dw, uw), Ifc_uart#(depth))
      Ifc_uart_axi4#(type iw, type aw, type dw, type uw, numeric type depth);*/


  typedef struct{
    ReservedZero#(20) zeros2;            // bit 31:12
    Bit#(4)           err_status;        // bit 11:8
    ReservedZero#(2)  zeros1;            // bit 7:6
    Bit#(1)           rx_thld;           // bit 5
    Bit#(1)           tx_thld;           // bit 4
    Bit#(1)           rx_notEmpty;       // bit 3
    Bit#(1)           rx_notFull ;       // bit 2
    Bit#(1)           tx_notFull ;       // bit 1
    Bit#(1)           tx_done    ;       // bit 0
  } UartStatus deriving (Bits, Eq, FShow);

  typedef struct{
    ReservedZero#(TSub#(16,TAdd#(n,n)))  zeros3;
    Bit#(n)           rx_thld;
    Bit#(n)           tx_thld;
    ReservedZero#(2)  zeros2;            // bits 15:14
    Bit#(1)           rx_thld_dirn;      // bit  13 
    Bit#(1)           tx_thld_dirn;      // bit  12
    Bit#(1)           rx_thld_auto_rst;  // bit  11
    Bit#(1)           tx_thld_auto_rst;  // bit  10
    ReservedZero#(2)  zeros1;            // bits 9:8
    Bit#(4)           charsize;          // bits 7:4
    Bit#(2)           parity;            // bits 3:2
    Bit#(2)           stop_bits;         // bits 1:0
  } UartControl#(numeric type n) deriving(Bits, Eq, FShow);

  typedef struct{
    Reserved#(24)     zeros;             // bits 31:8
    Bit#(8)           rx_data;           // bits 7:0
  } UartRx deriving(Bits, Eq, FShow);

  typedef struct {
    ReservedZero#(26) zeros;             // bits 31:6
    Bit#(1)           rx_thld;           // bit  5
    Bit#(1)           tx_thld;           // bit  4
    Bit#(4)           err_status;        // bits 3:0
  } UartClrStatus deriving (Bits, Eq, FShow);

  module [ModWithDCBus#(aw,dw)] mkuart_config_regs#(parameter Bit#(16) init_baud)
    (Ifc_uart#(depth))
		provisos(
      Add#(16, _a, aw),
      Add#(8, _b, dw),                // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw),        // dw is a proper multiple of 8 bits
      Log#(TAdd#(depth, 1), thld_sz), //thld_sz is the width of RX and TX threshold registers
      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(b__, TDiv#(dw, 8), 8),
      Add#(dw, d__, 32),
      Mul#(TDiv#(TAdd#(TSub#(16, TAdd#(thld_sz, thld_sz)), TAdd#(thld_sz,         //For threshold
           TAdd#(thld_sz, 16))), 8), 8, TAdd#(TSub#(16, TAdd#(thld_sz, thld_sz)), //field in Control
           TAdd#(thld_sz, TAdd#(thld_sz, 16))))                                   //Register
		);	

    DCRAddr#(aw,2) attr_baud           = DCRAddr {addr: 'h00, min: Sz2, max: Sz4, mask: 2'b00}; 
    DCRAddr#(aw,2) attr_tx             = DCRAddr {addr: 'h04, min: Sz1, max: Sz4, mask: 2'b00};
    DCRAddr#(aw,2) attr_rx             = DCRAddr {addr: 'h08, min: Sz1, max: Sz4, mask: 2'b00};
    DCRAddr#(aw,2) attr_status         = DCRAddr {addr: 'h0c, min: Sz1, max: Sz4, mask: 2'b00};
    DCRAddr#(aw,2) attr_cntrl          = DCRAddr {addr: 'h10, min: Sz1, max: Sz4, mask: 2'b00};
    DCRAddr#(aw,2) attr_clear_status   = DCRAddr {addr: 'h14, min: Sz1, max: Sz4, mask: 2'b00};
    DCRAddr#(aw,2) attr_interrupt_en   = DCRAddr {addr: 'h18, min: Sz1, max: Sz4, mask: 2'b00};
    

    UartControl#(thld_sz) resetValue= UartControl
        { rx_thld: 'd0,        //RX threshold set to 0
          tx_thld: 'd0,        //TX threshold set to 0
          rx_thld_dirn: 1,     //RX threshold direction set to greater than
          tx_thld_dirn: 0,     //TX threshold direction set to less than or equal to
          tx_thld_auto_rst: 0, //Disable autothreshold status reset for TX
          rx_thld_auto_rst: 1, //Enable autothreshold status reset for RX
          charsize: 'd8,       //8 bits in a character
          parity: 0,           //No Parity
          stop_bits: 0 };      //1 Stop bit

    PulseWire                             wr_deq_rx   <- mkPulseWire;
    
    Reg#(Bit#(16))                        rg_baud_val <- mkDCBRegRW(attr_baud, init_baud);
    RWire#(Bit#(8))                       wr_tx_char  <- mkDCBRWireW(attr_tx);
    Wire#(Bit#(SizeOf#(UartRx)))          rg_rx_char  <- mkDCBBypassWireROSe(attr_rx, wr_deq_rx.send);
    Wire#(Bit#(SizeOf#(UartStatus)))      wr_status   <- mkDCBBypassWireRO(attr_status); 
    Reg#(UartControl#(thld_sz))           rg_control  <- mkDCBRegRW(attr_cntrl, resetValue);
    RWire#(Bit#(SizeOf#(UartClrStatus)))  wr_clr_sts  <- mkDCBRWireW(attr_clear_status); 
    Reg#(Bit#(SizeOf#(UartStatus)))       rg_intr_en  <- mkDCBRegRW(attr_interrupt_en, 'd0); 

    UART#(depth) uart <- mkUART(unpack(rg_control.charsize), unpack(rg_control.parity),
                                unpack(rg_control.stop_bits), rg_baud_val,
                                unpack(rg_control.rx_thld), unpack(rg_control.tx_thld),
                                rg_control.rx_thld_dirn, rg_control.tx_thld_dirn,
                                rg_control.rx_thld_auto_rst, rg_control.tx_thld_auto_rst);

    (*fire_when_enabled*)
    rule rl_write_tx(wr_tx_char.wget matches tagged Valid .wr_tx_char_val);
      uart.send_char(wr_tx_char_val);
    endrule

    rule rl_clear_status(wr_clr_sts.wget matches tagged Valid .clr_status_val);
      uart.clear_status(truncate(pack(clr_status_val)));
    endrule

    (*no_implicit_conditions, fire_when_enabled*)
    rule rl_deq_rx(wr_deq_rx);
      uart.deq_receive_char;
    endrule:rl_deq_rx

    (*no_implicit_conditions, fire_when_enabled*)
    rule rl_connect_status;
      let _status = UartStatus{tx_done     : pack(uart.status.transmission_done),
                               tx_notFull  : pack(uart.status.transmittor_not_full),
                               rx_notFull  : pack(uart.status.receiver_not_full),
                               rx_notEmpty : pack(uart.status.receiver_not_empty),
                               tx_thld     : uart.status.thld_status[0],
                               rx_thld     : uart.status.thld_status[1],
                               err_status  : uart.status.err_status };
      wr_status  <= pack(_status);
      rg_rx_char <= pack(UartRx{rx_data:uart.receive_char});
    endrule

    interface io= uart.rs232;

    method Bit#(1) interrupt;
      return |(wr_status & rg_intr_en);
    endmethod
  endmodule

  module [Module] mkuart_block#(parameter Bit#(16) init_baud)
    (IWithDCBus#(DCBus#(aw,dw), Ifc_uart#(depth)))
		provisos(
      Add#(16, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

      Mul#(TDiv#(TAdd#(TSub#(16, TAdd#(TLog#(TAdd#(depth, 1)),         //For threshold field in 
           TLog#(TAdd#(depth, 1)))), TAdd#(TLog#(TAdd#(depth, 1)),     //Control regsiter
           TAdd#(TLog#(TAdd#(depth, 1)), 16))), 8), 8, TAdd#(TSub#(16,
           TAdd#(TLog#(TAdd#(depth, 1)), TLog#(TAdd#(depth, 1)))),
           TAdd#(TLog#(TAdd#(depth, 1)), TAdd#(TLog#(TAdd#(depth, 1)), 16)))),
      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(b__, TDiv#(dw, 8), 8),
      Add#(dw, d__, 32)
		);	
    let ifc <- exposeDCBusIFC(mkuart_config_regs(init_baud));
    return ifc;
  endmodule:mkuart_block

  module [Module] mkuart_axi4l#(parameter Bit#(16) baudrate, parameter Integer base, 
                                Clock uart_clk, Reset uart_rst)
  (Ifc_uart_axi4l#(aw, dw, uw, depth))
		provisos(
      Add#(16, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

      Mul#(TDiv#(TAdd#(TSub#(16, TAdd#(TLog#(TAdd#(depth, 1)),         //For threshold field in 
           TLog#(TAdd#(depth, 1)))), TAdd#(TLog#(TAdd#(depth, 1)),     //Control regsiter
           TAdd#(TLog#(TAdd#(depth, 1)), 16))), 8), 8, TAdd#(TSub#(16,
           TAdd#(TLog#(TAdd#(depth, 1)), TLog#(TAdd#(depth, 1)))),
           TAdd#(TLog#(TAdd#(depth, 1)), TAdd#(TLog#(TAdd#(depth, 1)), 16)))),
      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(b__, TDiv#(dw, 8), 8),
      Add#(dw, d__, 32)
		);	
    
    let uart_mod = mkuart_block(clocked_by uart_clk, reset_by uart_rst, baudrate);
    Ifc_uart_axi4l#(aw, dw, uw, depth) uart <- dc2axi4l(uart_mod, base, uart_clk, uart_rst);
    return uart;
  endmodule:mkuart_axi4l
  
  module [Module] mkuart_apb#(parameter Bit#(16) baudrate,parameter Integer base, 
                              Clock uart_clk, Reset uart_rst)
  (Ifc_uart_apb#(aw, dw, uw, depth))
		provisos(
      Add#(16, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

      Mul#(TDiv#(TAdd#(TSub#(16, TAdd#(TLog#(TAdd#(depth, 1)),         //For threshold field in 
           TLog#(TAdd#(depth, 1)))), TAdd#(TLog#(TAdd#(depth, 1)),     //Control regsiter
           TAdd#(TLog#(TAdd#(depth, 1)), 16))), 8), 8, TAdd#(TSub#(16,
           TAdd#(TLog#(TAdd#(depth, 1)), TLog#(TAdd#(depth, 1)))),
           TAdd#(TLog#(TAdd#(depth, 1)), TAdd#(TLog#(TAdd#(depth, 1)), 16)))),
      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(b__, TDiv#(dw, 8), 8),
      Add#(dw, d__, 32)
		);	
    
    let uart_mod = mkuart_block(clocked_by uart_clk, reset_by uart_rst, baudrate);
    Ifc_uart_apb#(aw, dw, uw, depth) uart<- dc2apb(uart_mod, base, uart_clk, uart_rst);
    return uart;
  endmodule:mkuart_apb
  


  /*module [Module] mkuart_axi4#(Clock uart_clk, Reset uart_rst,  parameter Bit#(16) baudrate)
    (Ifc_uart_axi4#(iw, aw, dw, uw, depth))
		provisos(
      Add#(16, _a, aw),
      Add#(8, _b, dw),         // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits

      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(b__, TDiv#(dw, 8), 8),
      Add#(dw, d__, 32)
		);	
    
    let uart_mod = mkuart_block(clocked_by uart_clk, reset_by uart_rst, baudrate);
    Ifc_uart_axi4#(iw, aw, dw, uw, depth) uart <-
        dc2axi4(uart_mod, uart_clk, uart_rst);
    return uart;
  endmodule:mkuart_axi4*/
 

endpackage:uart
