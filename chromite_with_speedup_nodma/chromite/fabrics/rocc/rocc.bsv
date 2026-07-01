// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Monday 24 January 2022 02:16:07 PM

*/
package rocc;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import Connectable  :: * ;
import Semi_FIFOF   :: * ;

`include "Logger.bsv"


function FIFOF_I #(t) fn_crg_and_rg_to_FIFOF_I (Reg #(Bool) rg_full, Reg #(t) rg_data);
	return interface FIFOF_I;
	  method Action enq (t x) if (! rg_full);
		  rg_full <= True;
  		rg_data <= x;
	  endmethod
	  method Bool notFull;
	  	return (! rg_full);
	  endmethod
	endinterface;
endfunction:fn_crg_and_rg_to_FIFOF_I

function FIFOF_O #(t) fn_crg_and_rg_to_FIFOF_O (Reg #(Bool) rg_full, Reg #(t) rg_data);
	return interface FIFOF_O;
    method t first () if (rg_full);
		  return rg_data;
	  endmethod
    method Action deq () if (rg_full);
  		rg_full <= False;
    endmethod
    method notEmpty;
  		return rg_full;
	  endmethod
	endinterface;
endfunction:fn_crg_and_rg_to_FIFOF_O
typedef struct{
  Bit#(32) instruction;
  Bit#(xlen) rs1;
  Bit#(xlen) rs2;
} RoccCommand#(numeric type xlen) deriving(Bits, FShow, Eq);

typedef struct{
  Bit#(xlen) data;
  Bit#(5)    rd;
  Bit#(causesize) cause;
  Bool trap;
} RoccResponse#(numeric type xlen, numeric type causesize) deriving (Bits, FShow, Eq);

interface Ifc_rocc_core#(numeric type xlen, numeric type causesize);
  (* always_ready, result="cmd_instruction" *) method Bit#(32) mv_instruction;
  (* always_ready, result="cmd_rs1" *) method Bit#(xlen) mv_rs1;
  (* always_ready, result="cmd_rs2" *) method Bit#(xlen) mv_rs2;
  (* always_ready, result="cmd_valid" *) method Bool mv_valid;

	(* always_ready, always_enabled, prefix = "" *)
  method Action ma_ready ((*port="cmd_ready"*) Bool rdy);

	(* always_ready, always_enabled, prefix = "" *)
  method Action ma_valid ((*port="resp_valid"*) Bool valid, 
                          (*port="resp_data"*) Bit#(xlen) data, 
                          (*port="resp_rd"*) Bit#(5) rd,
                          (*port="resp_trap"*) Bool trap,
                          (*port="resp_cause"*) Bit#(causesize) cause);
  (* always_ready, result="resp_ready" *)method Bool mv_ready;
endinterface:Ifc_rocc_core

interface Ifc_rocc_coproc#(numeric type xlen, numeric type causesize);
	(* always_ready, always_enabled, prefix = "" *)
  method Action ma_valid((*port="cmd_valid"*)Bool valid, 
                         (*port="cmd_instruction"*) Bit#(32) instruction, 
                         (*port="cmd_rs1"*) Bit#(xlen) rs1,
                         (*port="cmd_rs2"*) Bit#(xlen) rs2);
  
  (* always_ready, result="cmd_ready" *) method Bool mv_ready;

  (* always_ready, result="resp_data" *) method Bit#(xlen) mv_data;
  (* always_ready, result="resp_rd" *) method Bit#(5) mv_rd;
  (* always_ready, result="resp_trap" *) method Bool mv_trap;
  (* always_ready, result="resp_cause" *) method Bit#(causesize) mv_cause;
  (* always_ready, result="resp_valid" *) method Bool mv_valid;
	(* always_ready, always_enabled, prefix = "" *)
  method Action ma_ready ((*port="resp_ready"*)Bool rdy);
endinterface: Ifc_rocc_coproc

instance Connectable #(Ifc_rocc_core#(xlen, causesize), Ifc_rocc_coproc#(xlen, causesize));
  module mkConnection# (Ifc_rocc_core#(xlen, causesize) core, Ifc_rocc_coproc#(xlen, causesize) coproc)(Empty);

      (*fire_when_enabled, no_implicit_conditions*)
      /*doc:rule: */
      rule rl_connect_command;
        coproc.ma_valid(core.mv_valid, core.mv_instruction, core.mv_rs1, core.mv_rs2);
        core.ma_ready(coproc.mv_ready);
      endrule:rl_connect_command

      (*fire_when_enabled, no_implicit_conditions*)                  
      rule rl_connect_response;
        core.ma_valid(coproc.mv_valid, coproc.mv_data, coproc.mv_rd, coproc.mv_trap, coproc.mv_cause);
        coproc.ma_ready(core.mv_ready);
      endrule:rl_connect_response
    endmodule:mkConnection
endinstance:Connectable

instance Connectable#(Ifc_rocc_coproc#(xlen, causesize), Ifc_rocc_core#(xlen, causesize));
  module mkConnection# (Ifc_rocc_coproc#(xlen, causesize) coproc, Ifc_rocc_core#(xlen, causesize) core)(Empty);
    mkConnection(core, coproc);
  endmodule:mkConnection
endinstance:Connectable

interface Ifc_rocc_server#(numeric type xlen, numeric type causesize);
  interface FIFOF_I #(RoccCommand#(xlen)) i_cmd;
  interface FIFOF_O #(RoccResponse#(xlen, causesize)) o_resp;
endinterface:Ifc_rocc_server

interface Ifc_rocc_client#(numeric type xlen, numeric type causesize);
  interface FIFOF_O #(RoccCommand#(xlen)) o_cmd;
  interface FIFOF_I #(RoccResponse#(xlen, causesize)) i_resp;
endinterface:Ifc_rocc_client

interface Ifc_rocc_core_xactor#(numeric type xlen, numeric type causesize);
  interface Ifc_rocc_server#(xlen, causesize) fifo_side;
  interface Ifc_rocc_core#(xlen, causesize) rocc_side;
  method Action reset;
endinterface: Ifc_rocc_core_xactor

interface Ifc_rocc_coproc_xactor#(numeric type xlen, numeric type causesize);
  interface Ifc_rocc_client#(xlen, causesize) fifo_side;
  interface Ifc_rocc_coproc#(xlen, causesize) rocc_side;
  method Action reset;
endinterface: Ifc_rocc_coproc_xactor

module mk_rocc_core_xactor(Ifc_rocc_core_xactor#(xlen, causesize));
  
  Array#(Reg#(Bool)) crg_cmd_full <- mkCReg(3, False);
  Array#(Reg#(RoccCommand#(xlen))) crg_cmd <- mkCRegA(2,unpack(0));

  Array#(Reg#(Bool)) crg_resp_full <- mkCReg(3, False);
  Array#(Reg#(RoccResponse#(xlen, causesize))) crg_resp <- mkCRegA(2,unpack(0));

  Integer port_deq = 2;
  Integer port_enq = 1;
  Integer port_clear = 0;

  method Action reset;
    crg_cmd_full[port_clear] <= False;
    crg_resp_full[port_clear] <= False;
  endmethod:reset

  interface rocc_side = interface Ifc_rocc_core;
      method mv_instruction = crg_cmd[1].instruction;
      method mv_rs1 = crg_cmd[1].rs1;
      method mv_rs2 = crg_cmd[1].rs2;
      method mv_valid = crg_cmd_full [ port_deq];
      method Action ma_ready ( Bool rdy);
        if (crg_cmd_full[port_deq] && rdy) crg_cmd_full[port_deq] <= False;
      endmethod
      
      method Action ma_valid (Bool valid, Bit#(xlen) data, Bit#(5) rd, Bool trap, 
                              Bit#(causesize) cause);
        if (valid && !crg_resp_full[port_enq]) begin
          crg_resp_full[port_enq] <= True;
          crg_resp[0] <= RoccResponse{data: data, rd: rd, trap: trap, cause: cause};
        end
      endmethod
      method mv_ready = !crg_resp_full[port_enq];
  endinterface;

  interface fifo_side = interface Ifc_rocc_server
    interface i_cmd = fn_crg_and_rg_to_FIFOF_I (crg_cmd_full[port_enq], crg_cmd[0]);
    interface o_resp = fn_crg_and_rg_to_FIFOF_O (crg_resp_full[port_deq], crg_resp[1]);
  endinterface;

endmodule:mk_rocc_core_xactor

module mk_rocc_coproc_xactor(Ifc_rocc_coproc_xactor#(xlen, causesize));
  
  Array#(Reg#(Bool)) crg_cmd_full <- mkCReg(3, False);
  Array#(Reg#(RoccCommand#(xlen))) crg_cmd <- mkCRegA(2,unpack(0));

  Array#(Reg#(Bool)) crg_resp_full <- mkCReg(3, False);
  Array#(Reg#(RoccResponse#(xlen, causesize))) crg_resp <- mkCRegA(2,unpack(0));

  Integer port_deq = 1;
  Integer port_enq = 2;
  Integer port_clear = 0;

  method Action reset;
    crg_cmd_full[port_clear] <= False;
    crg_resp_full[port_clear] <= False;
  endmethod:reset

  interface rocc_side = interface Ifc_rocc_coproc;
    method mv_data = crg_resp[0].data;
    method mv_rd = crg_resp[0].rd;
    method mv_trap = crg_resp[0].trap;
    method mv_cause = crg_resp[0].cause;
    method mv_valid = crg_resp_full[port_deq];
    method Action ma_ready ( Bool rdy);
      if (crg_resp_full[port_deq] && rdy) crg_resp_full[port_deq] <= False;
    endmethod

    method Action ma_valid(Bool valid, Bit#(32) instruction, Bit#(xlen) rs1, Bit#(xlen) rs2);
      if (valid && !crg_cmd_full[port_enq]) begin
        crg_cmd_full[port_enq] <= True;
        crg_cmd[1] <= RoccCommand{instruction: instruction, rs1: rs1, rs2: rs2};
      end
    endmethod:ma_valid
  
    method mv_ready = !crg_cmd_full[port_enq];
  endinterface;

  interface fifo_side = interface Ifc_rocc_client
    interface o_cmd = fn_crg_and_rg_to_FIFOF_O (crg_cmd_full[port_deq], crg_cmd[0]);
    interface i_resp = fn_crg_and_rg_to_FIFOF_I (crg_resp_full[port_enq], crg_resp[1]);
  endinterface;

endmodule:mk_rocc_coproc_xactor

endpackage: rocc

