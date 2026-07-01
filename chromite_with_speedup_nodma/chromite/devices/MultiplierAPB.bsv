//See LICENSE.iitm for license details
/*
Author: Your Name
Email id: your.email@example.com
Description: APB-based Multiplier Accelerator using DCBus

This module implements a simple 32-bit multiplier accessible via APB interface.
It follows the same pattern as UART, using DCBus as an intermediate layer.

Register Map:
  Offset 0x00: OPERAND_A (write/read) - First operand
  Offset 0x04: OPERAND_B (write/read) - Second operand  
  Offset 0x08: RESULT_LO (read-only)  - Lower 32 bits of result
  Offset 0x0C: RESULT_HI (read-only)  - Upper 32 bits of result
  Offset 0x10: CONTROL   (write/read) - Control register
               [0]: START - Write 1 to start multiplication
               [1]: BUSY  - Read 1 when computing (read-only)
               [2]: DONE  - Read 1 when complete (read-only)
  Offset 0x14: STATUS    (read-only)  - Status register
               [31:0]: Number of completed operations

--------------------------------------------------------------------------------------------------
*/
package MultiplierAPB;

import GetPut       :: *;
import FIFO         :: *;
import ConfigReg    :: *;
import Clocks       :: *;
import BUtils       :: *;
import DefaultValue :: *;
import ModuleCollect:: *;
import Vector       :: *;
import Reserved     :: *;

import apb          :: *;
import DCBus        :: *;

// Export interface types
export Ifc_multiplier     (..);
export Ifc_multiplier_apb (..);
export mkmultiplier_apb;
export mkmultiplier_block;

// ============================================================================
// Interface Definitions
// ============================================================================

interface Ifc_multiplier;
  method Bit#(1) interrupt;  // Interrupt on completion
endinterface

typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Ifc_multiplier)
    Ifc_multiplier_apb#(type aw, type dw, type uw);

// ============================================================================
// Register Structure Definitions
// ============================================================================

typedef struct{
  ReservedZero#(29) zeros;      // bits 31:3
  Bit#(1)           done;       // bit 2
  Bit#(1)           busy;       // bit 1
  Bit#(1)           zero;       // bit 0 (START is write-only, always read as 0)
} MultiplierControl deriving (Bits, Eq, FShow);

typedef struct{
  Bit#(32)          op_count;   // bits 31:0
} MultiplierStatus deriving (Bits, Eq, FShow);

// ============================================================================
// Main Multiplier Configuration Module (using DCBus)
// ============================================================================

module [ModWithDCBus#(aw,dw)] mkmultiplier_config_regs(Ifc_multiplier)
  provisos(
    Add#(8, _a, aw),              // address width at least 8 bits
    Add#(8, _b, dw),              // data width at least 8 bits
    Mul#(TDiv#(dw,8), 8, dw),     // dw is a proper multiple of 8 bits
    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)), 0, dw),
    Add#(b__, TDiv#(dw, 8), 8),
    Add#(dw, d__, 32)
  );

  // DCBus register address attributes
  DCRAddr#(aw,2) attr_operand_a  = DCRAddr {addr: 'h00, min: Sz4, max: Sz4, mask: 2'b00}; 
  DCRAddr#(aw,2) attr_operand_b  = DCRAddr {addr: 'h04, min: Sz4, max: Sz4, mask: 2'b00};
  DCRAddr#(aw,2) attr_result_lo  = DCRAddr {addr: 'h08, min: Sz4, max: Sz4, mask: 2'b00};
  DCRAddr#(aw,2) attr_result_hi  = DCRAddr {addr: 'h0C, min: Sz4, max: Sz4, mask: 2'b00};
  DCRAddr#(aw,2) attr_control    = DCRAddr {addr: 'h10, min: Sz4, max: Sz4, mask: 2'b00};
  DCRAddr#(aw,2) attr_status     = DCRAddr {addr: 'h14, min: Sz4, max: Sz4, mask: 2'b00};
  
  // Registers for operands
  Reg#(Bit#(32)) rg_operand_a <- mkDCBRegRW(attr_operand_a, 0);
  Reg#(Bit#(32)) rg_operand_b <- mkDCBRegRW(attr_operand_b, 0);
  
  // Wires for result (read-only)
  Wire#(Bit#(32)) wr_result_lo <- mkDCBBypassWireRO(attr_result_lo);
  Wire#(Bit#(32)) wr_result_hi <- mkDCBBypassWireRO(attr_result_hi);
  
  // Control register (write for START, read for BUSY/DONE)
  RWire#(Bit#(32)) wr_control_wr <- mkDCBRWireW(attr_control);
  Wire#(Bit#(SizeOf#(MultiplierControl))) wr_control_rd <- mkDCBBypassWireRO(attr_control);
  
  // Status register (read-only)
  Wire#(Bit#(SizeOf#(MultiplierStatus))) wr_status <- mkDCBBypassWireRO(attr_status);
  
  // Internal state registers
  Reg#(Bit#(64)) rg_result      <- mkReg(0);
  Reg#(Bool)     rg_busy        <- mkReg(False);
  Reg#(Bool)     rg_done        <- mkReg(False);
  Reg#(Bit#(32)) rg_op_count    <- mkReg(0);
  Reg#(Bit#(3))  rg_compute_cycles <- mkReg(0);
  
  // ============================================================================
  // Rules
  // ============================================================================
  
  // Rule to handle START command
  rule rl_start_multiply(wr_control_wr.wget matches tagged Valid .ctrl_val &&& !rg_busy);
    if (ctrl_val[0] == 1) begin // START bit
      rg_busy <= True;
      rg_done <= False;
      rg_compute_cycles <= 0;
    end
  endrule
  
  // Rule to perform multiplication (simulates multi-cycle operation)
  rule rl_compute(rg_busy && rg_compute_cycles < 4);
    rg_compute_cycles <= rg_compute_cycles + 1;
    
    // Perform multiplication on last cycle
    if (rg_compute_cycles == 3) begin
      Bit#(64) result = zeroExtend(rg_operand_a) * zeroExtend(rg_operand_b);
      rg_result <= result;
      rg_busy <= False;
      rg_done <= True;
      rg_op_count <= rg_op_count + 1;
    end
  endrule
  
  // Rule to connect control register for reading
  (*no_implicit_conditions, fire_when_enabled*)
  rule rl_connect_control_read;
    let ctrl = MultiplierControl {
      done: pack(rg_done),
      busy: pack(rg_busy),
      zero: 0
    };
    wr_control_rd <= pack(ctrl);
  endrule
  
  // Rule to connect result registers
  (*no_implicit_conditions, fire_when_enabled*)
  rule rl_connect_result;
    wr_result_lo <= rg_result[31:0];
    wr_result_hi <= rg_result[63:32];
  endrule
  
  // Rule to connect status register
  (*no_implicit_conditions, fire_when_enabled*)
  rule rl_connect_status;
    let status = MultiplierStatus {
      op_count: rg_op_count
    };
    wr_status <= pack(status);
  endrule
  
  // ============================================================================
  // Interface Methods
  // ============================================================================
  
  method Bit#(1) interrupt;
    return pack(rg_done);  // Interrupt when operation completes
  endmethod

endmodule: mkmultiplier_config_regs

// ============================================================================
// DCBus Block Wrapper (exposes DCBus interface)
// ============================================================================

module [Module] mkmultiplier_block(IWithDCBus#(DCBus#(aw,dw), Ifc_multiplier))
  provisos(
    Add#(8, _a, aw),
    Add#(8, _b, dw),
    Mul#(TDiv#(dw,8), 8, dw),
    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)), 0, dw),
    Add#(b__, TDiv#(dw, 8), 8),
    Add#(dw, d__, 32)
  );
  
  let ifc <- exposeDCBusIFC(mkmultiplier_config_regs);
  return ifc;
  
endmodule: mkmultiplier_block

// ============================================================================
// APB Wrapper (converts DCBus to APB)
// ============================================================================

module [Module] mkmultiplier_apb#(parameter Integer base, Clock mult_clk, Reset mult_rst)
  (Ifc_multiplier_apb#(aw, dw, uw))
  provisos(
    Add#(8, _a, aw),
    Add#(8, _b, dw),
    Mul#(TDiv#(dw,8), 8, dw),
    Add#(a__, 2, aw),
    Add#(dw, c__, 64),
    Add#(TExp#(TLog#(dw)), 0, dw),
    Add#(b__, TDiv#(dw, 8), 8),
    Add#(dw, d__, 32)
  );
  
  let mult_mod = mkmultiplier_block(clocked_by mult_clk, reset_by mult_rst);
  Ifc_multiplier_apb#(aw, dw, uw) multiplier <- dc2apb(mult_mod, base, mult_clk, mult_rst);
  return multiplier;
  
endmodule: mkmultiplier_apb

endpackage: MultiplierAPB