// Copyright (c) InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Saturday 18 April 2020 10:34:40 PM IST

*/
package rom_user ;
import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import DReg         :: * ;
import BRAMCore     :: * ;

`include "Logger.bsv"

interface Ifc_rom_user #( numeric type entries, 
                          numeric type width,
                          numeric type banks);
  (*always_ready, always_enabled*)
  method Action ma_read  (Bit#(TAdd#(TLog#(entries),TLog#(TDiv#(width,8)))) addr);
  (*always_ready*)
  method Tuple2#(Bit#(width),Bool) mv_read_response;
endinterface:Ifc_rom_user

/*doc:module: */
module mk_rom_user #(parameter Vector#(banks,String) filename)
  (Ifc_rom_user#(entries, width, banks))
  provisos( Log# (entries, index_size),
            Div#(width, banks, bpb),
            Mul#(bpb, banks, width),
            Add#(a__, bpb, width));

  let v_entries = valueOf(entries);
  let v_banks   = valueOf(banks);
  let v_bpb     = valueOf(bpb);
  let v_offset  = valueOf(TLog#(TDiv#(width,8)));

  Vector #( banks, BRAM_PORT#( Bit#(TLog#(entries)), Bit#(bpb))) v_mem;
  for (Integer i = 0; i< v_banks; i = i + 1) begin
    v_mem[i] <- mkBRAMCore1Load(v_entries, False, filename[i], False);
  end
  
  method Action ma_read  (Bit#(TAdd#(TLog#(entries),TLog#(TDiv#(width,8)))) addr);
    addr = addr >> v_offset;
    for (Integer i = 0; i<v_banks; i = i + 1) begin
      v_mem[i].put(False, truncate(addr), ?) ;
    end
  endmethod:ma_read

  method Tuple2#(Bit#(width),Bool) mv_read_response;
    Bit#(width) _temp = ?;
    for (Integer i = 0; i< v_banks; i = i + 1) begin
      _temp[i*v_bpb+v_bpb - 1:i*v_bpb] = v_mem[i].read();
    end
    return tuple2(_temp, False);
  endmethod:mv_read_response
endmodule:mk_rom_user
endpackage: rom_user

